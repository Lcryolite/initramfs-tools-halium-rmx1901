#!/bin/sh
set -u

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$PROJECT_ROOT/tests/lib/fixture.sh"
POLICY_UNDER_TEST=${HALIUM_POLICY_UNDER_TEST:-$PROJECT_ROOT/scripts/halium-userdata}
. "$POLICY_UNDER_TEST"

halium_blkid() { "$FAKE_BIN/blkid" "$@"; }
halium_mount() { "$FAKE_BIN/mount" "$@"; }
halium_umount() { "$FAKE_BIN/umount" "$@"; }
halium_is_block() { "$FAKE_BIN/is-block" "$@"; }
halium_has_payload() { "$FAKE_BIN/has-payload" "$@"; }
halium_log() { "$FAKE_BIN/log" "$@"; }
halium_policy_panic() { "$FAKE_BIN/panic" "$@"; }

DEVICE=/dev/fake-userdata
MOUNTPOINT=/tmpmnt
failures=0

run_test() {
	test_name=$1
	fixture_start
	if "$test_name"; then
		printf 'ok - %s\n' "$test_name"
	else
		failures=$((failures + 1))
	fi
	fixture_stop
}

test_ext4_uses_readonly_probe_before_writable_mount() {
	BLKID_OUTPUT=ext4; export BLKID_OUTPUT
	assert_success safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
	assert_eq "$(cat "$CALL_LOG")" "is-block|$DEVICE
blkid|-s|TYPE|-o|value|$DEVICE
mount|-t|ext4|-o|ro,noload|$DEVICE|$MOUNTPOINT
has-payload|$MOUNTPOINT
umount|$MOUNTPOINT
mount|-t|ext4|-o|rw,noatime|$DEVICE|$MOUNTPOINT
log|userdata_mount=readwrite type=ext4 path=$DEVICE" "ext4 mount ordering/options changed"
}

test_f2fs_uses_f2fs_readonly_probe_before_writable_mount() {
	BLKID_OUTPUT=f2fs; export BLKID_OUTPUT
	assert_success safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
	assert_eq "$(cat "$CALL_LOG")" "is-block|$DEVICE
blkid|-s|TYPE|-o|value|$DEVICE
mount|-t|f2fs|-o|ro|$DEVICE|$MOUNTPOINT
has-payload|$MOUNTPOINT
umount|$MOUNTPOINT
mount|-t|f2fs|-o|rw,noatime|$DEVICE|$MOUNTPOINT
log|userdata_mount=readwrite type=f2fs path=$DEVICE" "f2fs mount ordering/options changed"
}

test_unknown_type_panics_without_mounting() {
	BLKID_OUTPUT=erofs; export BLKID_OUTPUT
	assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
	assert_eq "$(cat "$CALL_LOG")" "is-block|$DEVICE
blkid|-s|TYPE|-o|value|$DEVICE
panic|Unsupported or ambiguous userdata filesystem type" "unknown type reached mount"
}

test_multiline_type_panics_without_mounting() {
	BLKID_OUTPUT='ext4
f2fs'; export BLKID_OUTPUT
	assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
	assert_eq "$(cat "$CALL_LOG")" "is-block|$DEVICE
blkid|-s|TYPE|-o|value|$DEVICE
panic|Unsupported or ambiguous userdata filesystem type" "multiline type reached mount"
}

test_empty_type_panics_without_mounting() {
	BLKID_OUTPUT=; export BLKID_OUTPUT
	assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
	assert_eq "$(cat "$CALL_LOG")" "is-block|$DEVICE
blkid|-s|TYPE|-o|value|$DEVICE
panic|Unsupported or ambiguous userdata filesystem type" "empty type reached mount"
}

test_non_block_device_panics_before_blkid() {
	IS_BLOCK=0; export IS_BLOCK
	assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
	assert_eq "$(cat "$CALL_LOG")" "is-block|$DEVICE
panic|Userdata path is not a block device" "non-block path reached blkid or mount"
}

test_readonly_probe_failure_panics_without_writable_mount() {
	FAIL_RO=1; export FAIL_RO
	assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
	assert_eq "$(cat "$CALL_LOG")" "is-block|$DEVICE
blkid|-s|TYPE|-o|value|$DEVICE
mount|-t|ext4|-o|ro,noload|$DEVICE|$MOUNTPOINT
panic|Could not probe userdata read-only" "failed probe continued"
}

test_unmount_failure_panics_without_writable_mount() {
	FAIL_UMOUNT=1; export FAIL_UMOUNT
	assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
	assert_eq "$(cat "$CALL_LOG")" "is-block|$DEVICE
blkid|-s|TYPE|-o|value|$DEVICE
mount|-t|ext4|-o|ro,noload|$DEVICE|$MOUNTPOINT
has-payload|$MOUNTPOINT
umount|$MOUNTPOINT
panic|Could not unmount userdata read-only probe" "failed unmount continued"
}

test_writable_failure_remounts_readonly_then_panics() {
	FAIL_RW=1; export FAIL_RW
	assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
	assert_eq "$(cat "$CALL_LOG")" "is-block|$DEVICE
blkid|-s|TYPE|-o|value|$DEVICE
mount|-t|ext4|-o|ro,noload|$DEVICE|$MOUNTPOINT
has-payload|$MOUNTPOINT
umount|$MOUNTPOINT
mount|-t|ext4|-o|rw,noatime|$DEVICE|$MOUNTPOINT
mount|-t|ext4|-o|ro,noload|$DEVICE|$MOUNTPOINT
log|userdata_mount=readonly-rescue type=ext4 path=$DEVICE
panic|Could not mount userdata read-write; left in read-only rescue mode" "rw failure did not enter read-only rescue"
}

test_missing_payload_stays_readonly_and_panics() {
	HAS_PAYLOAD=0; export HAS_PAYLOAD
	assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
	assert_eq "$(cat "$CALL_LOG")" "is-block|$DEVICE
blkid|-s|TYPE|-o|value|$DEVICE
mount|-t|ext4|-o|ro,noload|$DEVICE|$MOUNTPOINT
has-payload|$MOUNTPOINT
log|userdata_mount=readonly-rescue type=ext4 path=$DEVICE
panic|No RMX1901 rootfs payload found on userdata" "missing payload reached writable mount"
}

for test_case in \
	test_ext4_uses_readonly_probe_before_writable_mount \
	test_f2fs_uses_f2fs_readonly_probe_before_writable_mount \
	test_unknown_type_panics_without_mounting \
	test_multiline_type_panics_without_mounting \
	test_empty_type_panics_without_mounting \
	test_non_block_device_panics_before_blkid \
	test_readonly_probe_failure_panics_without_writable_mount \
	test_unmount_failure_panics_without_writable_mount \
	test_writable_failure_remounts_readonly_then_panics \
	test_missing_payload_stays_readonly_and_panics
do
	run_test "$test_case"
done

[ "$failures" -eq 0 ]
