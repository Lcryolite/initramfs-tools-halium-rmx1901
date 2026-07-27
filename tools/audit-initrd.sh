#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$PROJECT_ROOT/tools/archive-lib.sh"
BASE_INIT_PATCH=$PROJECT_ROOT/patches/0001-rmx1901-record-base-init-handoff-events.patch
M1_SPEC_ORDER_GATE=$PROJECT_ROOT/tools/check-m1-spec-order.sh
M1_SPEC_ORDER_SPEC=$PROJECT_ROOT/config/m1-event-order-spec.md

BASE_IMAGE=${1:?usage: audit-initrd.sh BASE DERIVED BEFORE_MANIFEST AFTER_MANIFEST}
DERIVED_IMAGE=${2:?usage: audit-initrd.sh BASE DERIVED BEFORE_MANIFEST AFTER_MANIFEST}
RECORDED_BEFORE=${3:?usage: audit-initrd.sh BASE DERIVED BEFORE_MANIFEST AFTER_MANIFEST}
RECORDED_AFTER=${4:?usage: audit-initrd.sh BASE DERIVED BEFORE_MANIFEST AFTER_MANIFEST}
PINNED_BASE_SHA=0bbac4577f3567aec935c958216de5d30c7355452ca56248d6728f4f2634bdb6
BASE_SNAPSHOT_TOOL=$PROJECT_ROOT/tools/snapshot-regular-file.py

if ! "$M1_SPEC_ORDER_GATE" "$M1_SPEC_ORDER_SPEC"; then
	printf 'M1 source/spec order gate failed\n' >&2
	exit 20
fi

AUDIT_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rmx1901-initrd-audit.XXXXXX")
trap 'rm -rf "$AUDIT_ROOT"' EXIT HUP INT TERM
BASE_SNAPSHOT=$AUDIT_ROOT/base.snapshot
DERIVED_SNAPSHOT=$AUDIT_ROOT/derived.snapshot
RECORDED_BEFORE_SNAPSHOT=$AUDIT_ROOT/before-manifest.snapshot
RECORDED_AFTER_SNAPSHOT=$AUDIT_ROOT/after-manifest.snapshot
"$BASE_SNAPSHOT_TOOL" "$BASE_IMAGE" "$BASE_SNAPSHOT"
"$BASE_SNAPSHOT_TOOL" "$DERIVED_IMAGE" "$DERIVED_SNAPSHOT"
"$BASE_SNAPSHOT_TOOL" "$RECORDED_BEFORE" "$RECORDED_BEFORE_SNAPSHOT"
"$BASE_SNAPSHOT_TOOL" "$RECORDED_AFTER" "$RECORDED_AFTER_SNAPSHOT"
actual_base_sha=$(sha256sum "$BASE_SNAPSHOT" | awk '{print $1}')
if [ "$actual_base_sha" != "$PINNED_BASE_SHA" ]; then
	printf 'base initrd SHA-256 mismatch: expected %s, got %s\n' "$PINNED_BASE_SHA" "$actual_base_sha" >&2
	exit 1
fi
extract_initrd "$BASE_SNAPSHOT" "$AUDIT_ROOT/base"
extract_initrd "$DERIVED_SNAPSHOT" "$AUDIT_ROOT/derived"
test -f "$BASE_INIT_PATCH" || {
	printf 'RMX1901 base-init handoff patch is missing: %s\n' "$BASE_INIT_PATCH" >&2
	exit 1
}
mkdir "$AUDIT_ROOT/expected-init"
cp "$AUDIT_ROOT/base/init" "$AUDIT_ROOT/expected-init/init"
(cd "$AUDIT_ROOT/expected-init" && patch --batch --fuzz=0 -p1 <"$BASE_INIT_PATCH") || {
	printf 'RMX1901 base-init handoff patch did not apply during audit\n' >&2
	exit 1
}
cmp "$AUDIT_ROOT/expected-init/init" "$AUDIT_ROOT/derived/init"
manifest_tree "$AUDIT_ROOT/base" "$AUDIT_ROOT/before.manifest"
manifest_tree "$AUDIT_ROOT/derived" "$AUDIT_ROOT/after.manifest"
cmp "$RECORDED_BEFORE_SNAPSHOT" "$AUDIT_ROOT/before.manifest"
cmp "$RECORDED_AFTER_SNAPSHOT" "$AUDIT_ROOT/after.manifest"

write_delta_manifest "$AUDIT_ROOT/before.manifest" "$AUDIT_ROOT/after.manifest" "$AUDIT_ROOT/delta.manifest"
expected_delta='ADD scripts/halium-rmx1901-debug
ADD scripts/halium-userdata
DELETE sbin/dumpe2fs
DELETE sbin/e2fsck
DELETE sbin/resize2fs
REPLACE init
REPLACE scripts/halium'
[ "$(cat "$AUDIT_ROOT/delta.manifest")" = "$expected_delta" ] || {
	printf 'audit rejected non-allowlisted delta:\n' >&2
	cat "$AUDIT_ROOT/delta.manifest" >&2
	exit 1
}

for forbidden_tool in e2fsck resize2fs dumpe2fs mke2fs fsck.f2fs fsck.f2fs.static; do
	if [ -e "$AUDIT_ROOT/derived/sbin/$forbidden_tool" ] || [ -e "$AUDIT_ROOT/derived/bin/$forbidden_tool" ]; then
		printf 'forbidden executable remains: %s\n' "$forbidden_tool" >&2
		exit 1
	fi
done

if grep -E '[;&|[:space:]](e2fsck|resize2fs|dumpe2fs|mke2fs|mkfs(\.[^;&|[:space:]]*)?|fsck\.f2fs)([;&|[:space:]]|$)' \
	"$AUDIT_ROOT/derived/scripts/halium" \
	"$AUDIT_ROOT/derived/scripts/halium-userdata" \
	"$AUDIT_ROOT/derived/scripts/halium-rmx1901-debug"; then
	printf 'forbidden filesystem mutation command appears in boot control path\n' >&2
	exit 1
fi

if grep -E '(^|[,[:space:]])(discard|data=journal)([,[:space:]]|$)' \
	"$AUDIT_ROOT/derived/scripts/halium" \
	"$AUDIT_ROOT/derived/scripts/halium-userdata" \
	"$AUDIT_ROOT/derived/scripts/halium-rmx1901-debug"; then
	printf 'forbidden userdata mount option appears in boot control path\n' >&2
	exit 1
fi

cmp "$PROJECT_ROOT/scripts/halium" "$AUDIT_ROOT/derived/scripts/halium"
cmp "$PROJECT_ROOT/scripts/halium-userdata" "$AUDIT_ROOT/derived/scripts/halium-userdata"
cmp "$PROJECT_ROOT/scripts/halium-rmx1901-debug" "$AUDIT_ROOT/derived/scripts/halium-rmx1901-debug"
sh -n "$AUDIT_ROOT/derived/scripts/halium"
for handoff_stage in \
	CMDLINE_PARSED ROOT_DEVICE_RESOLVED USERDATA_PROBED ROOTFS_MOUNTED \
	DEV_MOVE_BEGIN DEV_MOVE_DONE CONSOLE_OPEN_OK CONSOLE_OPEN_FAILED \
	RUN_MOVE_BEGIN RUN_MOVE_DONE HANDOFF_MARKER_VISIBLE HANDOFF_MARKER_MISSING RUN_INIT_EXEC; do
	if ! grep -Fq "$handoff_stage" "$AUDIT_ROOT/derived/scripts/halium"; then
		printf 'handoff event vocabulary missing: %s\n' "$handoff_stage" >&2
		exit 1
	fi
done
if ! grep -Fq '>>"$RMX1901_HANDOFF_LOG"' "$AUDIT_ROOT/derived/scripts/halium" ||
	! grep -Fq '>/dev/kmsg' "$AUDIT_ROOT/derived/scripts/halium"; then
	printf 'handoff event sink is not append-only tmpfs plus kmsg\n' >&2
	exit 1
fi
for handoff_stage in DEV_MOVE_BEGIN DEV_MOVE_DONE CONSOLE_OPEN_OK CONSOLE_OPEN_FAILED \
	RUN_MOVE_BEGIN RUN_MOVE_DONE HANDOFF_MARKER_VISIBLE HANDOFF_MARKER_MISSING RUN_INIT_EXEC; do
	if ! grep -Fq "$handoff_stage" "$AUDIT_ROOT/derived/init"; then
		printf 'base-init handoff event missing: %s\n' "$handoff_stage" >&2
		exit 1
	fi
done
printf 'audit ok: allowlisted delta only; forbidden tools/commands/options absent\n'
