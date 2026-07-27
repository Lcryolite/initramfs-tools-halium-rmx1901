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
halium_canonical_path() { "$FAKE_BIN/canonical-path" "$@"; }
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

test_valid_rmx1901_systempart_allows_userdata_without_legacy_payload() {
	HAS_PAYLOAD=0; export HAS_PAYLOAD
	assert_success validate_rmx1901_systempart_cmdline \
		'console=tty0 systempart=/dev/block/by-name/system androidboot.mode=normal' || return 1
	assert_success safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
	assert_eq "$(cat "$CALL_LOG")" "canonical-path|/dev/block/by-name/system
is-block|/dev/block/sda11
is-block|$DEVICE
blkid|-s|TYPE|-o|value|$DEVICE
mount|-t|ext4|-o|ro,noload|$DEVICE|$MOUNTPOINT
has-payload|$MOUNTPOINT
log|userdata_payload=system-partition path=/dev/block/by-name/system
umount|$MOUNTPOINT
mount|-t|ext4|-o|rw,noatime|$DEVICE|$MOUNTPOINT
log|userdata_mount=readwrite type=ext4 path=$DEVICE" "validated system partition did not allow payload-free userdata safely"
}

test_no_systempart_keeps_legacy_payload_requirement() {
	HAS_PAYLOAD=0; export HAS_PAYLOAD
	assert_success validate_rmx1901_systempart_cmdline 'console=tty0 androidboot.mode=normal' || return 1
	assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
	assert_eq "$(cat "$CALL_LOG")" "is-block|$DEVICE
blkid|-s|TYPE|-o|value|$DEVICE
mount|-t|ext4|-o|ro,noload|$DEVICE|$MOUNTPOINT
has-payload|$MOUNTPOINT
log|userdata_mount=readonly-rescue type=ext4 path=$DEVICE
panic|No RMX1901 rootfs payload found on userdata" "legacy payload requirement was weakened without systempart"
}

test_unset_systempart_state_keeps_legacy_payload_requirement() {
	HAS_PAYLOAD=0; export HAS_PAYLOAD
	unset rmx1901_systempart
	assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
	assert_eq "$(cat "$CALL_LOG")" "is-block|$DEVICE
blkid|-s|TYPE|-o|value|$DEVICE
mount|-t|ext4|-o|ro,noload|$DEVICE|$MOUNTPOINT
has-payload|$MOUNTPOINT
log|userdata_mount=readonly-rescue type=ext4 path=$DEVICE
panic|No RMX1901 rootfs payload found on userdata" "unset validation state did not fail closed to legacy policy"
}

assert_systempart_rejected() {
	cmdline=$1
	expected_calls=$2
	assert_failure validate_rmx1901_systempart_cmdline "$cmdline" || return 1
	assert_eq "$(cat "$CALL_LOG")" "$expected_calls" "unsafe systempart was accepted"
}

test_raw_canonical_system_path_is_not_an_allowed_cmdline_alias() {
	assert_systempart_rejected \
		'systempart=/dev/block/sda11' \
		'panic|Unsafe RMX1901 systempart command-line value'
}

test_dynamic_partition_path_is_rejected() {
	assert_systempart_rejected \
		'systempart=/dev/block/mapper/system' \
		'panic|Unsafe RMX1901 systempart command-line value'
}

test_other_by_name_partition_is_rejected() {
	assert_systempart_rejected \
		'systempart=/dev/block/by-name/vendor' \
		'panic|Unsafe RMX1901 systempart command-line value'
}

test_system_alias_resolving_elsewhere_is_rejected() {
	CANONICAL_PATH=/dev/block/sde15; export CANONICAL_PATH
	assert_systempart_rejected \
		'systempart=/dev/block/by-name/system' \
		"canonical-path|/dev/block/by-name/system
panic|RMX1901 systempart canonical target mismatch"
}

test_non_block_canonical_system_target_is_rejected() {
	IS_BLOCK=0; export IS_BLOCK
	assert_systempart_rejected \
		'systempart=/dev/block/by-name/system' \
		"canonical-path|/dev/block/by-name/system
is-block|/dev/block/sda11
panic|RMX1901 systempart canonical target is not a block device"
}

test_duplicate_systempart_arguments_are_rejected() {
	assert_systempart_rejected \
		'systempart=/dev/block/by-name/system systempart=/dev/block/by-name/system' \
		'panic|Multiple systempart command-line values'
}

test_malformed_systempart_value_is_rejected_without_path_resolution() {
	assert_systempart_rejected \
		'systempart=/dev/block/by-name/system;reboot' \
		'panic|Unsafe RMX1901 systempart command-line value'
}

test_systempart_glob_is_rejected_even_when_cwd_can_expand_it_to_allowlisted_path() {
	mkdir -p "$FIXTURE_ROOT/systempart=/dev/block/by-name"
	: >"$FIXTURE_ROOT/systempart=/dev/block/by-name/system"
	original_directory=$PWD
	cd "$FIXTURE_ROOT" || return 1
	assert_failure validate_rmx1901_systempart_cmdline \
		'systempart=/dev/block/by-name/*' || {
			cd "$original_directory" || return 1
			return 1
		}
	cd "$original_directory" || return 1
	assert_eq "$(cat "$CALL_LOG")" \
		'panic|Unsafe RMX1901 systempart command-line value' \
		'glob-expanded systempart bypassed the literal allowlist'
}

test_systempart_alias_is_revalidated_after_userdata_before_mount() {
	CANONICAL_PATH_AFTER_FIRST=/dev/block/sde15; export CANONICAL_PATH_AFTER_FIRST
	assert_success validate_rmx1901_systempart_cmdline \
		'systempart=/dev/block/by-name/system' || return 1
	assert_failure safe_mount_rmx1901_systempart /halium-system || return 1
	assert_eq "$(cat "$CALL_LOG")" "canonical-path|/dev/block/by-name/system
is-block|/dev/block/sda11
canonical-path|/dev/block/by-name/system
panic|RMX1901 systempart changed before mount" "systempart alias TOCTOU was not rejected"
}

test_systempart_mount_uses_saved_canonical_path_and_propagates_failure() {
	FAIL_SYSTEM_MOUNT=1; export FAIL_SYSTEM_MOUNT
	assert_success validate_rmx1901_systempart_cmdline \
		'systempart=/dev/block/by-name/system' || return 1
	assert_failure safe_mount_rmx1901_systempart /halium-system || return 1
	assert_eq "$(cat "$CALL_LOG")" "canonical-path|/dev/block/by-name/system
is-block|/dev/block/sda11
canonical-path|/dev/block/by-name/system
is-block|/dev/block/sda11
mount|-o|rw|/dev/block/sda11|/halium-system
panic|Could not mount validated RMX1901 system partition" "systempart mount failure was ignored or alias was mounted"
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
	test_missing_payload_stays_readonly_and_panics \
	test_valid_rmx1901_systempart_allows_userdata_without_legacy_payload \
	test_no_systempart_keeps_legacy_payload_requirement \
	test_unset_systempart_state_keeps_legacy_payload_requirement \
	test_raw_canonical_system_path_is_not_an_allowed_cmdline_alias \
	test_dynamic_partition_path_is_rejected \
	test_other_by_name_partition_is_rejected \
	test_system_alias_resolving_elsewhere_is_rejected \
	test_non_block_canonical_system_target_is_rejected \
	test_duplicate_systempart_arguments_are_rejected \
	test_malformed_systempart_value_is_rejected_without_path_resolution \
	test_systempart_glob_is_rejected_even_when_cwd_can_expand_it_to_allowlisted_path \
	test_systempart_alias_is_revalidated_after_userdata_before_mount \
	test_systempart_mount_uses_saved_canonical_path_and_propagates_failure
do
	run_test "$test_case"
done

[ "$failures" -eq 0 ]
