#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rmx1901-derive-test.XXXXXX")
OUT_ONE=$TEST_ROOT/out-one
OUT_TWO=$TEST_ROOT/out-two
BASE_IMAGE=${PINNED_BASE_IMAGE:-/var/tmp/rmx1901-halium-initrd-cache/92015679-0bbac4577f3567aec935c958216de5d30c7355452ca56248d6728f4f2634bdb6-initrd.img-touch-arm64}
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

[ -f "$BASE_IMAGE" ] || fail "pinned base fixture unavailable: $BASE_IMAGE"

"$PROJECT_ROOT/tools/derive-initrd.sh" "$BASE_IMAGE" "$OUT_ONE"
"$PROJECT_ROOT/tools/derive-initrd.sh" "$BASE_IMAGE" "$OUT_TWO"
(
	cd "$TEST_ROOT"
	"$PROJECT_ROOT/tools/derive-initrd.sh" "$BASE_IMAGE" relative-out
)
[ -f "$TEST_ROOT/relative-out/initrd.img-touch-arm64-rmx1901-safe" ] || fail "relative output path was not resolved before packing"

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

BASE_EXTRACTED=$TEST_ROOT/base-extracted
DERIVED_EXTRACTED=$TEST_ROOT/derived-extracted
mkdir "$BASE_EXTRACTED" "$DERIVED_EXTRACTED"
(
	cd "$BASE_EXTRACTED"
	gzip -dc "$BASE_IMAGE" | cpio -idm --no-absolute-filenames 2>/dev/null
)
(
	cd "$DERIVED_EXTRACTED"
	gzip -dc "$OUT_ONE/initrd.img-touch-arm64-rmx1901-safe" | cpio -idm --no-absolute-filenames 2>/dev/null
)
cmp "$BASE_EXTRACTED/etc/fstab" "$DERIVED_EXTRACTED/etc/fstab" || fail "unrelated file content changed"
for tool in e2fsck resize2fs dumpe2fs; do
	[ ! -e "$DERIVED_EXTRACTED/sbin/$tool" ] || fail "$tool remains in derived initrd"
done
[ -f "$DERIVED_EXTRACTED/scripts/halium-userdata" ] || fail "safe policy missing from derived initrd"
[ -f "$DERIVED_EXTRACTED/scripts/halium-rmx1901-debug" ] || fail "diagnostic policy missing from derived initrd"
for stage in DEV_MOVE_BEGIN DEV_MOVE_DONE CONSOLE_OPEN_OK CONSOLE_OPEN_FAILED \
  RUN_MOVE_BEGIN RUN_MOVE_DONE HANDOFF_MARKER_VISIBLE HANDOFF_MARKER_MISSING RUN_INIT_EXEC; do
  grep -Fq "$stage" "$DERIVED_EXTRACTED/init" || fail "base init event is missing: $stage"
done
HALIUM_POLICY_UNDER_TEST="$DERIVED_EXTRACTED/scripts/halium-userdata" \
	/bin/sh "$PROJECT_ROOT/tests/test-safe-userdata.sh" >/dev/null || fail "packed policy behavior failed"
HALIUM_POLICY_UNDER_TEST="$DERIVED_EXTRACTED/scripts/halium-userdata" \
	/bin/sh "$PROJECT_ROOT/tests/test-handoff-semantics.sh" >/dev/null || fail "packed handoff semantics failed"
RMX1901_DEBUG_POLICY_UNDER_TEST="$DERIVED_EXTRACTED/scripts/halium-rmx1901-debug" \
	/bin/sh "$PROJECT_ROOT/tests/test-debug-rndis.sh" >/dev/null || fail "packed diagnostic policy behavior failed"

expected_delta='ADD scripts/halium-rmx1901-debug
ADD scripts/halium-userdata
DELETE sbin/dumpe2fs
DELETE sbin/e2fsck
DELETE sbin/resize2fs
REPLACE init
REPLACE scripts/halium'
[ "$(cat "$OUT_ONE/initrd.delta.manifest")" = "$expected_delta" ] || fail "archive changed paths outside allowlist"

created=$(jq -r '.creationInfo.created' "$OUT_ONE/initrd.spdx.json")
[ "$created" = 2023-01-17T13:46:06Z ] || fail "SBOM epoch does not match pinned release timestamp"
[ "$(jq -r '.packages[0].versionInfo' "$OUT_ONE/initrd.spdx.json")" = rmx1901-safe-debug-v1 ] ||
	fail "SBOM diagnostic version is stale"
[ -s "$OUT_ONE/initrd.img-touch-arm64-rmx1901-safe.sha256" ] || fail "artifact hash record missing"
printf 'ok - deterministic pinned derivation, allowlist delta, tool removal, audit, and metadata\n'
