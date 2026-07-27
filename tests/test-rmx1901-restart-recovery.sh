#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILDER=${RMX1901_RECOVERY_BUILDER_UNDER_TEST:-$PROJECT_ROOT/tools/build-rmx1901-restart-recovery.sh}
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rmx1901-restart-recovery.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

require_instruction_sequence() {
	remaining=$1
	while IFS= read -r instruction; do
		[ -n "$instruction" ] || continue
		match=$(printf '%s\n' "$remaining" | grep -n -F -m 1 "$instruction" || true)
		[ -n "$match" ] || fail "helper is missing ABI instruction: $instruction"
		remaining=$(printf '%s\n' "$remaining" | sed "1,${match%%:*}d")
	done <<'EOF'
mov	x0, #0xdead
movk	x0, #0xfee1, lsl #16
mov	x1, #0x1969
movk	x1, #0x2812, lsl #16
mov	x2, #0xc3d4
movk	x2, #0xa1b2, lsl #16
adr	x3,
mov	x8, #0x8e
svc	#0x0
mov	x0, #0x1
mov	x8, #0x5d
svc	#0x0
EOF
}

HELPER=$TEST_ROOT/rmx1901-restart-recovery
"$BUILDER" "$HELPER"

[ -x "$HELPER" ] || fail 'builder did not create an executable helper'
readelf -h "$HELPER" | grep -Fq 'Class:                             ELF64' ||
	fail 'helper is not ELF64'
readelf -h "$HELPER" | grep -Fq 'Machine:                           AArch64' ||
	fail 'helper is not AArch64'
if readelf -lW "$HELPER" | grep -Fq 'INTERP'; then
	fail 'helper has a program interpreter'
fi
readelf -dW "$HELPER" | grep -Fq 'There is no dynamic section in this file.' ||
	fail 'helper has a dynamic section'
[ "$(strings -a "$HELPER" | grep -Fxc recovery)" -eq 1 ] ||
	fail 'helper does not contain exactly one fixed recovery target'

START_DISASSEMBLY=$(aarch64-linux-gnu-objdump -d "$HELPER" |
	sed -n '/<_start>:/,/^$/p')
require_instruction_sequence "$START_DISASSEMBLY"

# A freestanding entry point must not read the startup stack, where argc/argv
# reside.  The fixed ABI sequence above supplies every syscall register.
if printf '%s\n' "$START_DISASSEMBLY" | grep -Eq '[[:space:]]sp([,]|$)'; then
	fail 'helper reads the startup stack and may accept arguments'
fi

printf 'ok - static AArch64 recovery restart helper has no argument interface\n'
