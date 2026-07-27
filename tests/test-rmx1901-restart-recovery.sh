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
[ "$(strings -a "$HELPER" | grep -Fxc recovery)" -eq 1 ] ||
	fail 'helper does not contain exactly one fixed recovery target'

# A freestanding entry point must not read the startup stack, where argc/argv
# reside.  Its fixed syscall ABI therefore accepts no executable arguments.
if aarch64-linux-gnu-objdump -d "$HELPER" | grep -Eq '[[:space:]]sp([,]|$)'; then
	fail 'helper reads the startup stack and may accept arguments'
fi

printf 'ok - static AArch64 recovery restart helper has no argument interface\n'
