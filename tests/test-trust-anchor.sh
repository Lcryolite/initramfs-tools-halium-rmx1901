#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rmx1901-trust-anchor.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
PINNED_BASE_IMAGE=${PINNED_BASE_IMAGE:-/var/tmp/rmx1901-halium-initrd-cache/92015679-0bbac4577f3567aec935c958216de5d30c7355452ca56248d6728f4f2634bdb6-initrd.img-touch-arm64}

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

printf 'untrusted base\n' >"$TEST_ROOT/untrusted.img"
untrusted_sha=$(sha256sum "$TEST_ROOT/untrusted.img" | awk '{print $1}')
if EXPECTED_BASE_SHA=$untrusted_sha \
	"$PROJECT_ROOT/tools/derive-initrd.sh" "$TEST_ROOT/untrusted.img" "$TEST_ROOT/untrusted-out" \
	>"$TEST_ROOT/derive.stdout" 2>"$TEST_ROOT/derive.stderr"; then
	fail "environment replaced the production base trust anchor"
fi
grep -q 'base initrd SHA-256 mismatch' "$TEST_ROOT/derive.stderr" || fail "derive rejection was not the fixed-hash gate"

: >"$TEST_ROOT/empty.manifest"
if "$PROJECT_ROOT/tools/audit-initrd.sh" \
	"$TEST_ROOT/untrusted.img" "$TEST_ROOT/untrusted.img" \
	"$TEST_ROOT/empty.manifest" "$TEST_ROOT/empty.manifest" \
	>"$TEST_ROOT/audit.stdout" 2>"$TEST_ROOT/audit.stderr"; then
	fail "auditor accepted an untrusted base"
fi
grep -q 'base initrd SHA-256 mismatch' "$TEST_ROOT/audit.stderr" || fail "audit rejection was not the fixed-hash gate"

[ -f "$PINNED_BASE_IMAGE" ] || fail "pinned base fixture unavailable: $PINNED_BASE_IMAGE"
SOURCE_DATE_EPOCH=1 "$PROJECT_ROOT/tools/derive-initrd.sh" "$PINNED_BASE_IMAGE" "$TEST_ROOT/fixed-epoch-out"
created=$(jq -r '.creationInfo.created' "$TEST_ROOT/fixed-epoch-out/initrd.spdx.json")
[ "$created" = 2023-01-17T13:46:06Z ] || fail "environment replaced the fixed production epoch"

printf 'ok - base SHA and release epoch are immutable production trust anchors\n'
