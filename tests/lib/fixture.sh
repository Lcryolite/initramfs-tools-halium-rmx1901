#!/bin/sh

FIXTURE_ROOT=${TMPDIR:-/tmp}/rmx1901-initrd-test.$$
FAKE_BIN=$FIXTURE_ROOT/bin
CALL_LOG=$FIXTURE_ROOT/calls.log

fixture_start() {
	rm -rf "$FIXTURE_ROOT"
	mkdir -p "$FAKE_BIN"
	: >"$CALL_LOG"
	for command_name in blkid mount umount is-block has-payload log panic; do
		ln -s "$PROJECT_ROOT/tests/helpers/fake-command.sh" "$FAKE_BIN/$command_name"
	done
	export CALL_LOG
	export BLKID_OUTPUT=ext4 IS_BLOCK=1 HAS_PAYLOAD=1
	export FAIL_RO=0 FAIL_RW=0 FAIL_UMOUNT=0
	export HALIUM_BLKID=$FAKE_BIN/blkid
	export HALIUM_MOUNT=$FAKE_BIN/mount
	export HALIUM_UMOUNT=$FAKE_BIN/umount
	export HALIUM_IS_BLOCK=$FAKE_BIN/is-block
	export HALIUM_HAS_PAYLOAD=$FAKE_BIN/has-payload
	export HALIUM_LOG=$FAKE_BIN/log
	export HALIUM_PANIC=$FAKE_BIN/panic
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
