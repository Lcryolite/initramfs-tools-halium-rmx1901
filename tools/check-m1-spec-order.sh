#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SPEC=${1:?usage: check-m1-spec-order.sh AUTHORITATIVE_SPEC}
HALIUM_SOURCE=${2:-$PROJECT_ROOT/scripts/halium}
BASE_INIT_PATCH=${3:-$PROJECT_ROOT/patches/0001-rmx1901-record-base-init-handoff-events.patch}
MARKER=$PROJECT_ROOT/config/m1-event-order-contract.env

blocked() {
	printf 'M1_SPEC_ALIGNMENT=BLOCKED\n'
	printf 'M1_SPEC_ALIGNMENT_REASON=%s\n' "$1"
	exit 20
}

[ -f "$SPEC" ] || blocked SPEC_MISSING
[ -f "$HALIUM_SOURCE" ] || blocked HALIUM_SOURCE_MISSING
[ -f "$BASE_INIT_PATCH" ] || blocked BASE_INIT_PATCH_MISSING
[ -f "$MARKER" ] || blocked SOURCE_ORDER_MARKER_MISSING
grep -Fxq 'M1_EVENT_ORDER_SCHEMA=RMX1901-M1-HANDOFF-V1' "$MARKER" || blocked MARKER_SCHEMA_MISMATCH
grep -Fxq 'M1_EVENT_ORDER_STATUS=ALIGNED' "$MARKER" || blocked MARKER_NOT_ALIGNED
grep -Fxq 'M1_EVENT_ORDER_REQUIREMENT=USERDATA_PROBED_BEFORE_ROOTFS_MOUNTED' "$MARKER" ||
	blocked MARKER_REQUIREMENT_MISMATCH
grep -Fxq 'M1_EVENT_ORDER_SEQUENCE=CMDLINE_PARSED:ROOT_DEVICE_RESOLVED:USERDATA_PROBED:ROOTFS_MOUNTED:DEV_MOVE_BEGIN:DEV_MOVE_DONE:CONSOLE_OPEN:RUN_MOVE_BEGIN:RUN_MOVE_DONE:HANDOFF_MARKER:RUN_INIT_EXEC' "$MARKER" ||
	blocked MARKER_SEQUENCE_MISMATCH

section=$(awk '
	/^## 9[.]/ { inside = 1; next }
	inside && /^## / { exit }
	inside { print }
' "$SPEC") || blocked SPEC_SECTION_READ_FAILED
[ -n "$section" ] || blocked SPEC_SECTION_9_MISSING
userdata_count=$(printf '%s\n' "$section" | grep -c '`USERDATA_PROBED`' || true)
rootfs_count=$(printf '%s\n' "$section" | grep -c '`ROOTFS_MOUNTED`' || true)
[ "$userdata_count" -ge 1 ] || blocked USERDATA_STAGE_MISSING
[ "$rootfs_count" -ge 1 ] || blocked ROOTFS_STAGE_MISSING
userdata_line=$(printf '%s\n' "$section" | grep -n '`USERDATA_PROBED`' | head -n 1 | cut -d: -f1)
rootfs_line=$(printf '%s\n' "$section" | grep -n '`ROOTFS_MOUNTED`' | head -n 1 | cut -d: -f1)
[ "$userdata_line" -lt "$rootfs_line" ] || blocked NONCAUSAL_USERDATA_ROOTFS_ORDER

source_emissions=$(
	awk '
		/rmx1901_handoff_event [A-Z_]+ / {
			line = $0
			sub(/^.*rmx1901_handoff_event /, "", line)
			sub(/ .*/, "", line)
			print line
		}
	' "$HALIUM_SOURCE" "$BASE_INIT_PATCH"
) || blocked SOURCE_EMISSION_READ_FAILED
expected_emissions='CMDLINE_PARSED
ROOT_DEVICE_RESOLVED
USERDATA_PROBED
ROOTFS_MOUNTED
DEV_MOVE_BEGIN
DEV_MOVE_DONE
CONSOLE_OPEN_OK
CONSOLE_OPEN_FAILED
RUN_MOVE_BEGIN
RUN_MOVE_DONE
HANDOFF_MARKER_VISIBLE
HANDOFF_MARKER_MISSING
RUN_INIT_EXEC'
[ "$source_emissions" = "$expected_emissions" ] || blocked SOURCE_STAGE_EMISSION_MISMATCH

printf 'M1_SPEC_ALIGNMENT=PASS\n'
printf 'M1_SPEC_ALIGNMENT_ORDER=USERDATA_PROBED_BEFORE_ROOTFS_MOUNTED\n'
