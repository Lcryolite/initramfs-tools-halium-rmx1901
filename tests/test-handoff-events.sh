#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HALIUM=$PROJECT_ROOT/scripts/halium

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

sh -n "$HALIUM" || fail 'halium shell syntax is invalid'

# The logger must never truncate or persist evidence outside initramfs tmpfs.
grep -Fq '>>"$RMX1901_HANDOFF_LOG"' "$HALIUM" || fail 'handoff log is not append-only'
grep -Fq '>/dev/kmsg' "$HALIUM" || fail 'handoff events are not mirrored to kmsg'
grep -Fq 'RMX1901_HANDOFF_LOG=${RMX1901_HANDOFF_LOG:-/run/rmx1901-handoff.events}' "$HALIUM" ||
	fail 'handoff log is not located on initramfs tmpfs'

for stage in \
	CMDLINE_PARSED ROOT_DEVICE_RESOLVED USERDATA_PROBED ROOTFS_MOUNTED \
	DEV_MOVE_BEGIN DEV_MOVE_DONE CONSOLE_OPEN_OK CONSOLE_OPEN_FAILED \
	RUN_MOVE_BEGIN RUN_MOVE_DONE HANDOFF_MARKER_VISIBLE HANDOFF_MARKER_MISSING RUN_INIT_EXEC; do
	grep -Fq "$stage" "$HALIUM" ||
		fail "stage missing from ordered vocabulary: $stage"
done

line_for() {
	grep -n -F "rmx1901_handoff_event $1 " "$HALIUM" | head -n 1 | cut -d: -f1
}

cmdline_line=$(line_for CMDLINE_PARSED)
devices_line=$(line_for ROOT_DEVICE_RESOLVED)
userdata_line=$(line_for USERDATA_PROBED)
rootfs_line=$(line_for ROOTFS_MOUNTED)
[ -n "$cmdline_line" ] && [ -n "$devices_line" ] && [ -n "$userdata_line" ] && [ -n "$rootfs_line" ] ||
	fail 'mountroot does not emit all currently-owned handoff stages'
[ "$cmdline_line" -lt "$devices_line" ] && [ "$devices_line" -lt "$userdata_line" ] && [ "$userdata_line" -lt "$rootfs_line" ] ||
	fail 'currently-owned handoff stages are out of order'

printf 'ok - append-only ordered M1 handoff event contract\n'
