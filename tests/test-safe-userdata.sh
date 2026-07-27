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
halium_mount_table() {
  probe_source=${PROBE_MOUNT_SOURCE:-/dev/sda13}
  probe_fstype=${PROBE_MOUNT_FSTYPE:-$BLKID_OUTPUT}
  if [ -n "${PROBE_MOUNT_OPTIONS-}" ]; then
    probe_options=$PROBE_MOUNT_OPTIONS
  elif [ "$probe_fstype" = f2fs ]; then
    probe_options=ro,norecovery
  else
    probe_options=ro,noload
  fi
  printf '%s %s %s %s 0 0\n' "$probe_source" "$MOUNTPOINT" "$probe_fstype" "$probe_options"
  [ "${PROBE_MOUNT_DUPLICATE-0}" != 1 ] ||
    printf '%s %s %s %s 0 0\n' "$probe_source" "$MOUNTPOINT" "$probe_fstype" "$probe_options"
}
halium_mountinfo() {
  probe_source=${PROBE_MOUNT_SOURCE:-/dev/sda13}
  probe_fstype=${PROBE_MOUNT_FSTYPE:-$BLKID_OUTPUT}
  probe_mm=${PROBE_MOUNT_MM:-8:13}
  if [ -n "${PROBE_MOUNT_OPTIONS-}" ]; then
    probe_options=$PROBE_MOUNT_OPTIONS
  elif [ "$probe_fstype" = f2fs ]; then
    probe_options=ro,norecovery
  else
    probe_options=ro,noload
  fi
  probe_super_options=${PROBE_MOUNT_SUPER_OPTIONS:-$probe_options}
  printf '101 1 %s / %s %s - %s %s %s\n' \
    "$probe_mm" "$MOUNTPOINT" "$probe_options" \
    "$probe_fstype" "$probe_source" "$probe_super_options"
  [ "${PROBE_MOUNT_DUPLICATE-0}" != 1 ] ||
    printf '102 1 %s / %s %s - %s %s %s\n' \
      "$probe_mm" "$MOUNTPOINT" "$probe_options" \
      "$probe_fstype" "$probe_source" "$probe_super_options"
}
halium_block_sectors_by_mountinfo_mm() {
  if [ -n "${PROBE_MOUNT_SECTORS-}" ]; then
    printf '%s\n' "$PROBE_MOUNT_SECTORS"
  else
    case "$1" in
      8:11) printf '%s\n' 10182656 ;;
      8:13) printf '%s\n' 105199512 ;;
      *) return 1 ;;
    esac
  fi
}

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

test_f2fs_probe_rejects_nonunique_or_unsafe_mounted_state() {
  BLKID_OUTPUT=f2fs; PROBE_MOUNT_DUPLICATE=1; export BLKID_OUTPUT PROBE_MOUNT_DUPLICATE
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq "umount|$MOUNTPOINT" "$CALL_LOG" || return 1
  grep -Fxq 'panic|Unsafe or ambiguous userdata read-only probe mount' "$CALL_LOG" || return 1
  ! grep -q '^dmesg$\|^has-payload|' "$CALL_LOG"
}

test_f2fs_probe_rejects_rw_or_missing_norecovery_mount_options() {
  BLKID_OUTPUT=f2fs; PROBE_MOUNT_OPTIONS=rw,norecovery; export BLKID_OUTPUT PROBE_MOUNT_OPTIONS
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq "umount|$MOUNTPOINT" "$CALL_LOG" || return 1
  grep -Fxq 'panic|Unsafe or ambiguous userdata read-only probe mount' "$CALL_LOG" || return 1
  fixture_start
  BLKID_OUTPUT=f2fs; PROBE_MOUNT_OPTIONS=ro; export BLKID_OUTPUT PROBE_MOUNT_OPTIONS
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq "umount|$MOUNTPOINT" "$CALL_LOG" || return 1
  grep -Fxq 'panic|Unsafe or ambiguous userdata read-only probe mount' "$CALL_LOG"
}

test_f2fs_probe_rejects_rw_in_superblock_options_before_safe_evidence() {
  BLKID_OUTPUT=f2fs; PROBE_MOUNT_OPTIONS=ro,norecovery
  PROBE_MOUNT_SUPER_OPTIONS=rw,norecovery
  export BLKID_OUTPUT PROBE_MOUNT_OPTIONS PROBE_MOUNT_SUPER_OPTIONS
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq "umount|$MOUNTPOINT" "$CALL_LOG" || return 1
  grep -Fxq 'panic|Unsafe or ambiguous userdata read-only probe mount' "$CALL_LOG" || return 1
  ! grep -q '^dmesg$\|^has-payload|' "$CALL_LOG" || return 1
  [ -z "${rmx1901_userdata_probe_facts-}" ]
}

test_probe_mount_rejection_reports_failed_cleanup_as_own_panic() {
  BLKID_OUTPUT=f2fs; PROBE_MOUNT_OPTIONS=rw,norecovery; FAIL_UMOUNT=1
  export BLKID_OUTPUT PROBE_MOUNT_OPTIONS FAIL_UMOUNT
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq 'panic|Could not unmount userdata read-only probe' "$CALL_LOG" || return 1
  ! grep -Fq 'panic|Unsafe or ambiguous userdata read-only probe mount' "$CALL_LOG"
}

test_probe_mount_major_minor_is_bound_before_evidence_reads() {
  BLKID_OUTPUT=f2fs; PROBE_MOUNT_MM=8:12
  export BLKID_OUTPUT PROBE_MOUNT_MM
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq "umount|$MOUNTPOINT" "$CALL_LOG" || return 1
  grep -Fxq 'panic|Unsafe or ambiguous userdata read-only probe mount' "$CALL_LOG" || return 1
  ! grep -q '^dmesg$\|^has-payload|' "$CALL_LOG"
}

test_probe_mount_superblock_size_is_bound_before_evidence_reads() {
  BLKID_OUTPUT=f2fs; PROBE_MOUNT_SECTORS=1
  export BLKID_OUTPUT PROBE_MOUNT_SECTORS
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  grep -Fxq "umount|$MOUNTPOINT" "$CALL_LOG" || return 1
  grep -Fxq 'panic|Unsafe or ambiguous userdata read-only probe mount' "$CALL_LOG" || return 1
  ! grep -q '^dmesg$\|^has-payload|' "$CALL_LOG"
}

test_systempart_actual_mount_rejects_changed_major_minor_or_size() (
  halium_canonical_path() { printf '%s\n' /dev/sda11; }
  halium_is_block() { return 0; }
  halium_major_minor() { printf '%s\n' "${SYSTEM_MM:-8:b}"; }
  halium_block_size() { printf '%s\n' "${SYSTEM_SIZE:-5213519872}"; }
  halium_mount() { "$FAKE_BIN/mount" "$@"; }
  halium_policy_panic() { "$FAKE_BIN/panic" "$@"; }
  rmx1901_systempart=/dev/disk/by-partlabel/system
  rmx1901_systempart_canonical=/dev/sda11

  SYSTEM_MM=8:c; export SYSTEM_MM
  assert_failure safe_mount_rmx1901_systempart /halium-system || return 1
  ! grep -q '^mount|' "$CALL_LOG" || return 1
  grep -Fxq 'panic|RMX1901 systempart identity changed before mount' "$CALL_LOG" || return 1

  fixture_start
  SYSTEM_MM=8:b; SYSTEM_SIZE=1; export SYSTEM_MM SYSTEM_SIZE
  rmx1901_systempart=/dev/disk/by-partlabel/system
  rmx1901_systempart_canonical=/dev/sda11
  assert_failure safe_mount_rmx1901_systempart /halium-system || return 1
  ! grep -q '^mount|' "$CALL_LOG" || return 1
  grep -Fxq 'panic|RMX1901 systempart identity changed before mount' "$CALL_LOG"
)

test_systempart_mount_is_readonly_and_binds_mounted_superblock() (
  halium_canonical_path() { printf '%s\n' /dev/sda11; }
  halium_is_block() { return 0; }
  halium_major_minor() { printf '%s\n' 8:b; }
  halium_block_size() { printf '%s\n' 5213519872; }
  halium_mount() { "$FAKE_BIN/mount" "$@"; }
  halium_umount() { "$FAKE_BIN/umount" "$@"; }
  halium_policy_panic() { "$FAKE_BIN/panic" "$@"; }
  halium_mountinfo() {
    printf '201 1 %s / /halium-system %s - ext4 /dev/sda11 %s\n' \
      "${SYSTEM_MOUNT_MM:-8:11}" "${SYSTEM_MOUNT_OPTIONS:-ro}" "${SYSTEM_SUPER_OPTIONS:-ro}"
  }
  halium_block_sectors_by_mountinfo_mm() { printf '%s\n' "${SYSTEM_MOUNT_SECTORS:-10182656}"; }
  rmx1901_systempart=/dev/disk/by-partlabel/system
  rmx1901_systempart_canonical=/dev/sda11

  assert_success safe_mount_rmx1901_systempart /halium-system || return 1
  grep -Fxq 'mount|-o|ro|/dev/sda11|/halium-system' "$CALL_LOG" || return 1
  ! grep -Fq 'mount|-o|rw|' "$CALL_LOG" || return 1

  fixture_start
  rmx1901_systempart=/dev/disk/by-partlabel/system
  rmx1901_systempart_canonical=/dev/sda11
  SYSTEM_MOUNT_OPTIONS=rw; SYSTEM_SUPER_OPTIONS=rw; export SYSTEM_MOUNT_OPTIONS SYSTEM_SUPER_OPTIONS
  assert_failure safe_mount_rmx1901_systempart /halium-system || return 1
  grep -Fxq 'umount|/halium-system' "$CALL_LOG" || return 1
  grep -Fxq 'panic|Mounted RMX1901 system superblock identity mismatch' "$CALL_LOG" || return 1

  fixture_start
  rmx1901_systempart=/dev/disk/by-partlabel/system
  rmx1901_systempart_canonical=/dev/sda11
  SYSTEM_MOUNT_MM=8:12; export SYSTEM_MOUNT_MM
  assert_failure safe_mount_rmx1901_systempart /halium-system || return 1
  grep -Fxq 'umount|/halium-system' "$CALL_LOG" || return 1
  grep -Fxq 'panic|Mounted RMX1901 system superblock identity mismatch' "$CALL_LOG" || return 1

  fixture_start
  rmx1901_systempart=/dev/disk/by-partlabel/system
  rmx1901_systempart_canonical=/dev/sda11
  SYSTEM_MOUNT_MM=8:11; SYSTEM_MOUNT_SECTORS=1; export SYSTEM_MOUNT_MM SYSTEM_MOUNT_SECTORS
  assert_failure safe_mount_rmx1901_systempart /halium-system || return 1
  grep -Fxq 'umount|/halium-system' "$CALL_LOG" || return 1
  grep -Fxq 'panic|Mounted RMX1901 system superblock identity mismatch' "$CALL_LOG"
)

test_missing_payload_unmounts_before_failure_panic() {
  HAS_PAYLOAD=0; export HAS_PAYLOAD
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  filtered=$(grep -E '^(has-payload|umount|panic)[|]' "$CALL_LOG")
  assert_eq "$filtered" "$(printf '%s\n' \
    "has-payload|$MOUNTPOINT" \
    "umount|$MOUNTPOINT" \
    'panic|No RMX1901 rootfs payload found on userdata')" \
    'userdata must be cleanly unmounted before a payload failure panic'
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

test_f2fs_unreadable_probe_log_fails_before_persistent_read() {
  BLKID_OUTPUT=f2fs; FAIL_DMESG=1; export BLKID_OUTPUT FAIL_DMESG
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  assert_eq "$(grep -E '^(mount[|]|dmesg$|umount[|]|panic[|])' "$CALL_LOG")" "$(printf '%s\n' \
    "mount|-t|f2fs|-o|ro,norecovery|/dev/sda13|$MOUNTPOINT" \
    'dmesg' \
    "umount|$MOUNTPOINT" \
    'panic|Could not collect F2FS read-only probe evidence')" 'unreadable F2FS evidence must fail after a readonly probe is unmounted' || return 1
  ! grep -q '^has-payload|' "$CALL_LOG"
}

test_f2fs_unreadable_probe_log_and_failed_unmount_never_reads_payload() {
  BLKID_OUTPUT=f2fs; FAIL_DMESG=1; FAIL_UMOUNT=1; export BLKID_OUTPUT FAIL_DMESG FAIL_UMOUNT
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  assert_eq "$(grep -E '^(mount[|]|dmesg$|umount[|]|panic[|])' "$CALL_LOG")" "$(printf '%s\n' \
    "mount|-t|f2fs|-o|ro,norecovery|/dev/sda13|$MOUNTPOINT" \
    'dmesg' \
    "umount|$MOUNTPOINT" \
    'panic|Could not unmount userdata read-only probe')" 'unmount failure after unreadable F2FS evidence must fail closed' || return 1
  ! grep -q '^has-payload|' "$CALL_LOG"
}

test_unknown_filesystem_never_mounts() {
  BLKID_OUTPUT=erofs; export BLKID_OUTPUT
  assert_failure safe_mount_userdata "$DEVICE" "$MOUNTPOINT" || return 1
  ! grep -q '^mount|' "$CALL_LOG"
}

for test_name in \
  test_f2fs_probe_is_exactly_readonly_and_never_writable \
  test_f2fs_probe_rejects_nonunique_or_unsafe_mounted_state \
  test_f2fs_probe_rejects_rw_or_missing_norecovery_mount_options \
  test_f2fs_probe_rejects_rw_in_superblock_options_before_safe_evidence \
  test_probe_mount_rejection_reports_failed_cleanup_as_own_panic \
  test_probe_mount_major_minor_is_bound_before_evidence_reads \
  test_probe_mount_superblock_size_is_bound_before_evidence_reads \
  test_systempart_actual_mount_rejects_changed_major_minor_or_size \
  test_systempart_mount_is_readonly_and_binds_mounted_superblock \
  test_missing_payload_unmounts_before_failure_panic \
  test_userdata_canonical_path_must_be_sda13 \
  test_userdata_major_minor_must_match \
  test_userdata_capacity_must_match \
  test_userdata_is_revalidated_after_probe_mount \
  test_userdata_major_minor_is_revalidated_after_probe_mount \
  test_userdata_capacity_is_revalidated_after_probe_mount \
  test_f2fs_recovery_log_fails_before_persistent_read \
  test_f2fs_unreadable_probe_log_fails_before_persistent_read \
  test_f2fs_unreadable_probe_log_and_failed_unmount_never_reads_payload \
  test_unknown_filesystem_never_mounts; do
  run_test "$test_name"
done

[ "$failures" -eq 0 ] || exit 1
printf 'safe_userdata_policy=pass\n'
