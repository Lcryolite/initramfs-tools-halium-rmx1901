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
halium_major_minor() { "$FAKE_BIN/major-minor" "$@"; }
halium_block_size() { "$FAKE_BIN/block-size" "$@"; }
halium_dmesg() { "$FAKE_BIN/dmesg" "$@"; }
halium_log() { "$FAKE_BIN/log" "$@"; }
halium_policy_panic() { "$FAKE_BIN/panic" "$@"; }

DEVICE=/dev/block/by-name/userdata
MOUNTPOINT=/tmpmnt
failures=0

run_test() { fixture_start; if "$1"; then printf 'ok - %s\n' "$1"; else failures=$((failures + 1)); fi; fixture_stop; }

test_f2fs_probe_is_exactly_readonly_and_never_writable() {
  BLKID_OUTPUT=f2fs; export BLKID_OUTPUT
  assert_success safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq "mount|-t|f2fs|-o|ro,norecovery|/dev/sda13|$MOUNTPOINT" "$CALL_LOG" || return 1
  ! grep -Fq 'rw,noatime' "$CALL_LOG"
}

test_userdata_canonical_path_must_be_sda13() {
  CANONICAL_PATH=/dev/sda12; export CANONICAL_PATH
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq 'panic|RMX1901 userdata canonical target mismatch' "$CALL_LOG"
}

test_userdata_major_minor_must_match() {
  MAJOR_MINOR=8:c; export MAJOR_MINOR
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq 'panic|RMX1901 userdata major:minor mismatch' "$CALL_LOG"
}

test_userdata_capacity_must_match() {
  BLOCK_SIZE=1; export BLOCK_SIZE
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq 'panic|RMX1901 userdata capacity mismatch' "$CALL_LOG"
}

test_userdata_is_revalidated_after_probe_mount() {
  CANONICAL_PATH_AFTER_FIRST=/dev/sda12; export CANONICAL_PATH_AFTER_FIRST
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq 'panic|RMX1901 userdata changed after read-only probe' "$CALL_LOG" || return 1
  grep -Fxq "umount|$MOUNTPOINT" "$CALL_LOG" || return 1
  ! grep -q '^has-payload|' "$CALL_LOG"
}

test_userdata_major_minor_is_revalidated_after_probe_mount() {
  MAJOR_MINOR_AFTER_FIRST=8:c; export MAJOR_MINOR_AFTER_FIRST
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq 'panic|RMX1901 userdata changed after read-only probe' "$CALL_LOG" || return 1
  grep -Fxq "umount|$MOUNTPOINT" "$CALL_LOG" || return 1
  ! grep -q '^has-payload|' "$CALL_LOG"
}

test_userdata_capacity_is_revalidated_after_probe_mount() {
  BLOCK_SIZE_AFTER_FIRST=1; export BLOCK_SIZE_AFTER_FIRST
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq 'panic|RMX1901 userdata changed after read-only probe' "$CALL_LOG" || return 1
  grep -Fxq "umount|$MOUNTPOINT" "$CALL_LOG" || return 1
  ! grep -q '^has-payload|' "$CALL_LOG"
}

test_f2fs_recovery_log_fails_before_persistent_read() {
  BLKID_OUTPUT=f2fs; DMESG_OUTPUT='f2fs: recover fsync data on readonly fs'; export BLKID_OUTPUT DMESG_OUTPUT
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq 'panic|F2FS recovery detected during read-only userdata probe' "$CALL_LOG" || return 1
  grep -Fxq "umount|$MOUNTPOINT" "$CALL_LOG" || return 1
  ! grep -q '^has-payload|' "$CALL_LOG"
}

test_unknown_filesystem_never_mounts() {
  BLKID_OUTPUT=erofs; export BLKID_OUTPUT
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  ! grep -q '^mount|' "$CALL_LOG"
}

for test_name in \
  test_f2fs_probe_is_exactly_readonly_and_never_writable \
  test_userdata_canonical_path_must_be_sda13 \
  test_userdata_major_minor_must_match \
  test_userdata_capacity_must_match \
  test_userdata_is_revalidated_after_probe_mount \
  test_userdata_major_minor_is_revalidated_after_probe_mount \
  test_userdata_capacity_is_revalidated_after_probe_mount \
  test_f2fs_recovery_log_fails_before_persistent_read \
  test_unknown_filesystem_never_mounts; do
  run_test "$test_name"
done

[ "$failures" -eq 0 ] || exit 1
printf 'safe_userdata_policy=pass\n'
