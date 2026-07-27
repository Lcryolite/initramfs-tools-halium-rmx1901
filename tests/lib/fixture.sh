#!/bin/sh

FIXTURE_ROOT=${TMPDIR:-/tmp}/rmx1901-initrd-test.$$
FAKE_BIN=$FIXTURE_ROOT/bin
CALL_LOG=$FIXTURE_ROOT/calls.log

fixture_start() {
	rm -rf "$FIXTURE_ROOT"
	mkdir -p "$FAKE_BIN"
	: >"$CALL_LOG"
	for command_name in blkid mount umount is-block has-payload canonical-path major-minor block-size dmesg log panic; do
		ln -s "$PROJECT_ROOT/tests/helpers/fake-command.sh" "$FAKE_BIN/$command_name"
	done
	export CALL_LOG
	export BLKID_OUTPUT=ext4 IS_BLOCK=1 HAS_PAYLOAD=1
	export CANONICAL_PATH=/dev/sda13 MAJOR_MINOR=8:d BLOCK_SIZE=53862150144
	unset CANONICAL_PATH_AFTER_FIRST MAJOR_MINOR_AFTER_FIRST BLOCK_SIZE_AFTER_FIRST DMESG_OUTPUT
	unset PROBE_MOUNT_SOURCE PROBE_MOUNT_FSTYPE PROBE_MOUNT_OPTIONS PROBE_MOUNT_DUPLICATE
	unset PROBE_MOUNT_MM PROBE_MOUNT_SECTORS PROBE_MOUNT_SUPER_OPTIONS
	export FAIL_RO=0 FAIL_RW=0 FAIL_UMOUNT=0 FAIL_SYSTEM_MOUNT=0 FAIL_DMESG=0
	# Poison the old environment injection interface. Production code must use
	# fixed wrapper functions, which this test shell overrides below.
	export HALIUM_BLKID=/bin/false HALIUM_MOUNT=/bin/false HALIUM_UMOUNT=/bin/false
	export HALIUM_IS_BLOCK=/bin/false HALIUM_HAS_PAYLOAD=/bin/false
	export HALIUM_LOG=/bin/false HALIUM_PANIC=/bin/false
	rmx1901_systempart=
	rmx1901_systempart_canonical=
}

fixture_stop() {
	rm -rf "$FIXTURE_ROOT"
}

fail() {
	printf 'not ok - %s\n' "$1" >&2
	return 1
}

assert_eq() {
	actual=$1
	expected=$2
	message=$3
	[ "$actual" = "$expected" ] || {
		printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
		fail "$message"
	}
}

assert_contains() {
	haystack=$1
	needle=$2
	message=$3
	case "$haystack" in
		*"$needle"*) ;;
		*) fail "$message" ;;
	esac
}

assert_success() {
	"$@" || fail "expected success: $*"
}

assert_failure() {
	if "$@"; then
		fail "expected failure: $*"
	fi
}
