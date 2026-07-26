#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=${TMPDIR:-/tmp}/rmx1901-derive-test.$$
BASE_ROOT=$TEST_ROOT/base-root
BASE_IMAGE=$TEST_ROOT/base.img
OUT_ONE=$TEST_ROOT/out-one
OUT_TWO=$TEST_ROOT/out-two
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

mkdir -p "$BASE_ROOT/scripts" "$BASE_ROOT/sbin" "$BASE_ROOT/etc"
printf '%s\n' '# legacy halium script' >"$BASE_ROOT/scripts/halium"
printf '%s\n' 'preserve this byte-for-byte' >"$BASE_ROOT/etc/unchanged"
for tool in e2fsck resize2fs dumpe2fs; do
	printf '%s\n' "forbidden $tool" >"$BASE_ROOT/sbin/$tool"
done
chmod 755 "$BASE_ROOT/scripts/halium" "$BASE_ROOT/sbin/"*
find "$BASE_ROOT" -exec touch -h -d @1700000000 {} +
(
	cd "$BASE_ROOT"
	find . -print0 | LC_ALL=C sort -z | cpio --null -o -H newc --reproducible --owner=0:0 2>/dev/null | gzip -n -9 >"$BASE_IMAGE"
)

EXPECTED_BASE_SHA=$(sha256sum "$BASE_IMAGE" | awk '{print $1}')
export EXPECTED_BASE_SHA SOURCE_DATE_EPOCH=1672920000

"$PROJECT_ROOT/tools/derive-initrd.sh" "$BASE_IMAGE" "$OUT_ONE"
"$PROJECT_ROOT/tools/derive-initrd.sh" "$BASE_IMAGE" "$OUT_TWO"
(
	cd "$TEST_ROOT"
	"$PROJECT_ROOT/tools/derive-initrd.sh" "$BASE_IMAGE" relative-out
)
[ -f "$TEST_ROOT/relative-out/initrd.img-touch-arm64-rmx1901-safe" ] || fail "relative output path was not resolved before packing"
(
	unset SOURCE_DATE_EPOCH
	"$PROJECT_ROOT/tools/derive-initrd.sh" "$BASE_IMAGE" "$TEST_ROOT/default-epoch-out"
)
default_created=$(jq -r '.creationInfo.created' "$TEST_ROOT/default-epoch-out/initrd.spdx.json")
[ "$default_created" = 2023-01-17T13:46:06Z ] || fail "default epoch does not match pinned release timestamp"

hash_one=$(sha256sum "$OUT_ONE/initrd.img-touch-arm64-rmx1901-safe" | awk '{print $1}')
hash_two=$(sha256sum "$OUT_TWO/initrd.img-touch-arm64-rmx1901-safe" | awk '{print $1}')
[ "$hash_one" = "$hash_two" ] || fail "two derivations are not byte-identical"

"$PROJECT_ROOT/tools/audit-initrd.sh" \
	"$BASE_IMAGE" \
	"$OUT_ONE/initrd.img-touch-arm64-rmx1901-safe" \
	"$OUT_ONE/initrd.before.manifest" \
	"$OUT_ONE/initrd.after.manifest"
(
	cd "$TEST_ROOT"
	"$PROJECT_ROOT/tools/audit-initrd.sh" \
		"$BASE_IMAGE" \
		out-one/initrd.img-touch-arm64-rmx1901-safe \
		out-one/initrd.before.manifest \
		out-one/initrd.after.manifest
)

EXTRACTED=$TEST_ROOT/extracted
mkdir "$EXTRACTED"
(
	cd "$EXTRACTED"
	gzip -dc "$OUT_ONE/initrd.img-touch-arm64-rmx1901-safe" | cpio -idm --no-absolute-filenames 2>/dev/null
)
cmp "$BASE_ROOT/etc/unchanged" "$EXTRACTED/etc/unchanged" || fail "unrelated file content changed"
for tool in e2fsck resize2fs dumpe2fs; do
	[ ! -e "$EXTRACTED/sbin/$tool" ] || fail "$tool remains in derived initrd"
done
[ -f "$EXTRACTED/scripts/halium-userdata" ] || fail "safe policy missing from derived initrd"
HALIUM_POLICY_UNDER_TEST="$EXTRACTED/scripts/halium-userdata" \
	/bin/sh "$PROJECT_ROOT/tests/test-safe-userdata.sh" >/dev/null || fail "packed policy behavior failed"

delta=$(cat "$OUT_ONE/initrd.delta.manifest")
expected_delta='ADD scripts/halium-userdata
DELETE sbin/dumpe2fs
DELETE sbin/e2fsck
DELETE sbin/resize2fs
REPLACE scripts/halium'
[ "$delta" = "$expected_delta" ] || {
	printf 'unexpected delta:\n%s\n' "$delta" >&2
	fail "archive changed paths outside allowlist"
}

[ -s "$OUT_ONE/initrd.spdx.json" ] || fail "SPDX SBOM missing"
[ -s "$OUT_ONE/initrd.img-touch-arm64-rmx1901-safe.sha256" ] || fail "artifact hash record missing"
printf 'ok - deterministic derivation, allowlist delta, tool removal, audit, and metadata\n'
