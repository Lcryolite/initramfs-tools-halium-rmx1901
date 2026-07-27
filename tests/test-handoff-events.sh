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
if grep -Fq '>>"$RMX1901_HANDOFF_LOG" 2>/dev/null || true' "$HALIUM"; then

	fail 'handoff logger silently accepts an unavailable evidence log'
fi
if grep -Fq '>/dev/kmsg 2>/dev/null || true' "$HALIUM"; then
	fail 'handoff logger silently accepts an unavailable kmsg mirror'
fi

BASE_INIT_PATCH="$PROJECT_ROOT/patches/0001-rmx1901-record-base-init-handoff-events.patch"
grep -Fq 'CONSOLE_OPEN_FAILED "path=${rootmnt}/dev/console open_status=${rmx1901_console_status}"' "$BASE_INIT_PATCH" ||
	fail 'console failure event has no explicit open status'
grep -Fq 'RUN_INIT_EXEC "init=${init} inode=${rmx1901_init_inode} type=${rmx1901_init_type}"' "$BASE_INIT_PATCH" ||
	fail 'run-init event has no init inode and type'

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
