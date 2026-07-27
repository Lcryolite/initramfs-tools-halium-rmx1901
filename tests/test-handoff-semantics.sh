#!/bin/sh
set -u

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$PROJECT_ROOT/tests/lib/fixture.sh"
POLICY_UNDER_TEST=${HALIUM_POLICY_UNDER_TEST:-$PROJECT_ROOT/scripts/halium-userdata}
. "$POLICY_UNDER_TEST"

failures=0

run_test() {
	fixture_start
	if "$1"; then
		printf 'ok - %s\n' "$1"
	else
		failures=$((failures + 1))
	fi
	fixture_stop
}

test_cmdline_facts_name_exact_required_tokens() {
	cmdline='console=ttyMSM0,115200n8 systempart=/dev/disk/by-partlabel/system systemd.unified_cgroup_hierarchy=0 console=tty0 rmx1901.debug_rndis=1'
	assert_success rmx1901_collect_cmdline_facts "$cmdline" || return 1
	assert_eq "${rmx1901_cmdline_facts-}" \
		'systempart=valid cgroup=valid console=valid diagnostic_rndis=valid' \
		'exact M1 command-line tokens must be named in evidence'
}

test_cmdline_facts_distinguish_missing_invalid_and_duplicate_tokens() {
	cmdline='systempart=/dev/disk/by-partlabel/wrong systemd.unified_cgroup_hierarchy=1 console=tty0 console=tty0'
	assert_success rmx1901_collect_cmdline_facts "$cmdline" || return 1
	assert_eq "${rmx1901_cmdline_facts-}" \
		'systempart=invalid cgroup=invalid console=duplicate diagnostic_rndis=missing' \
		'invalid, duplicate, and missing required tokens must not look valid'
}

test_cmdline_facts_reject_correct_plus_wrong_named_duplicates() {
	cmdline='systempart=/dev/disk/by-partlabel/system systempart=/dev/sda11 systemd.unified_cgroup_hierarchy=0 systemd.unified_cgroup_hierarchy=1 console=ttyMSM0,115200n8 console=tty0 console=ttyS0 rmx1901.debug_rndis=1 rmx1901.debug_rndis=0'
	assert_success rmx1901_collect_cmdline_facts "$cmdline" || return 1
	assert_eq "${rmx1901_cmdline_facts-}" \
		'systempart=duplicate cgroup=duplicate console=duplicate diagnostic_rndis=duplicate' \
		'a correct token plus a conflicting named token must not look valid'
}

test_root_device_facts_bind_all_three_canonical_devices() {
	halium_canonical_path() {
		case "$1" in
			/dev/disk/by-partlabel/system) printf '%s\n' /dev/sda11 ;;
			/dev/block/by-name/userdata) printf '%s\n' /dev/sda13 ;;
			*) return 1 ;;
		esac
	}
	halium_major_minor() {
		case "$1" in
			/dev/sda11) printf '%s\n' 8:b ;;
			/dev/sda13) printf '%s\n' 8:d ;;
			*) return 1 ;;
		esac
	}
	halium_is_block() { return 0; }
	halium_block_size() {
		case "$1" in
			/dev/sda11) printf '%s\n' 5213519872 ;;
			/dev/sda13) printf '%s\n' 53862150144 ;;
			*) return 1 ;;
		esac
	}
	assert_success rmx1901_collect_root_device_facts \
		/dev/disk/by-partlabel/system \
		/dev/disk/by-partlabel/system \
		/dev/block/by-name/userdata || return 1
	assert_eq "${rmx1901_root_device_facts-}" \
		'root=/dev/sda11 root_mm=8:b system=/dev/sda11 system_mm=8:b userdata=/dev/sda13 userdata_mm=8:d' \
		'root, system, and userdata identities must all be canonical and measured'
}

test_root_device_facts_reject_unmeasurable_identity() {
	halium_canonical_path() { printf '%s\n' "$1"; }
	halium_is_block() { return 0; }
	halium_block_size() { printf '%s\n' 1; }
	halium_major_minor() {
		[ "$1" != /dev/sda11 ] || return 1
		printf '%s\n' 8:d
	}
	assert_failure rmx1901_collect_root_device_facts /dev/sda11 /dev/sda11 /dev/sda13
}

test_root_device_facts_reject_nonblock_or_wrong_capacity() {
	halium_canonical_path() { printf '%s\n' "$1"; }
	halium_major_minor() {
		case "$1" in /dev/sda11) printf '%s\n' 8:b ;; /dev/sda13) printf '%s\n' 8:d ;; esac
	}
	halium_is_block() { [ "$1" != /dev/sda11 ]; }
	halium_block_size() {
		case "$1" in /dev/sda11) printf '%s\n' 5213519872 ;; /dev/sda13) printf '%s\n' 53862150144 ;; esac
	}
	assert_failure rmx1901_collect_root_device_facts /dev/sda11 /dev/sda11 /dev/sda13 || return 1
	halium_is_block() { return 0; }
	halium_block_size() {
		case "$1" in /dev/sda11) printf '%s\n' 1 ;; /dev/sda13) printf '%s\n' 53862150144 ;; esac
	}
	assert_failure rmx1901_collect_root_device_facts /dev/sda11 /dev/sda11 /dev/sda13
}

test_f2fs_probe_exports_norecovery_proof_only_after_clean_unmount() {
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
		printf '%s\n' '/dev/sda13 /tmpmnt f2fs ro,norecovery 0 0'
	}
	halium_mountinfo() {
		printf '%s\n' '101 1 8:13 / /tmpmnt ro,norecovery - f2fs /dev/sda13 ro,norecovery'
	}
	halium_block_sectors_by_mountinfo_mm() { printf '%s\n' 105199512; }
	BLKID_OUTPUT=f2fs
	export BLKID_OUTPUT
	assert_success safe_mount_userdata /dev/block/by-name/userdata /tmpmnt || return 1
	assert_eq "${rmx1901_userdata_probe_facts-}" \
		'path=/dev/sda13 major_minor=8:d fstype=f2fs readonly=yes norecovery=yes rw=absent dmesg=readable recovery_fsync=absent unmounted=yes result=safe' \
		'F2FS evidence must prove norecovery and absence of recovery writes'
}

test_failed_f2fs_unmount_never_exports_safe_probe_facts() {
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
		printf '%s\n' '/dev/sda13 /tmpmnt f2fs ro,norecovery 0 0'
	}
	halium_mountinfo() {
		printf '%s\n' '101 1 8:13 / /tmpmnt ro,norecovery - f2fs /dev/sda13 ro,norecovery'
	}
	halium_block_sectors_by_mountinfo_mm() { printf '%s\n' 105199512; }
	BLKID_OUTPUT=f2fs
	FAIL_UMOUNT=1
	export BLKID_OUTPUT FAIL_UMOUNT
	assert_failure safe_mount_userdata /dev/block/by-name/userdata /tmpmnt || return 1
	[ -z "${rmx1901_userdata_probe_facts-}" ] || fail 'failed probe exported a safe evidence record'
}

test_rootfs_mount_facts_record_unique_mounted_row() {
	halium_mount_table() {
		printf '%s\n' \
			'tmpfs /run tmpfs rw,nosuid,nodev 0 0' \
			'/dev/sda11 /halium-system ext4 ro,relatime,seclabel 0 0'
	}
	halium_mountinfo() {
		printf '%s\n' \
			'20 1 0:19 / /run rw,nosuid,nodev - tmpfs tmpfs rw,nosuid,nodev' \
			'21 1 8:11 / /halium-system ro,relatime,seclabel - ext4 /dev/sda11 ro,relatime,seclabel'
	}
	halium_block_sectors_by_mountinfo_mm() { printf '%s\n' 10182656; }
	assert_success rmx1901_collect_rootfs_mount_facts /halium-system /dev/sda11 || return 1
	assert_eq "${rmx1901_rootfs_mount_facts-}" \
		'requested_source=/dev/sda11 source=/dev/sda11 fstype=ext4 options=ro:relatime:seclabel' \
		'rootfs event must report the mounted source, fstype, and options'
}

test_rootfs_mount_facts_reject_missing_or_duplicate_rows() {
	halium_mount_table() { printf '%s\n' 'tmpfs /run tmpfs rw 0 0'; }
	halium_mountinfo() { printf '%s\n' '20 1 0:19 / /run rw - tmpfs tmpfs rw'; }
	halium_block_sectors_by_mountinfo_mm() { printf '%s\n' 10182656; }
	assert_failure rmx1901_collect_rootfs_mount_facts /halium-system /dev/sda11 || return 1
	halium_mount_table() {
		printf '%s\n' \
			'/dev/sda11 /halium-system ext4 ro 0 0' \
			'/dev/sda12 /halium-system ext4 ro 0 0'
	}
	halium_mountinfo() {
		printf '%s\n' \
			'21 1 8:11 / /halium-system ro - ext4 /dev/sda11 ro' \
			'22 1 8:12 / /halium-system ro - ext4 /dev/sda12 ro'
	}
	assert_failure rmx1901_collect_rootfs_mount_facts /halium-system /dev/sda11
}

for test_name in \
	test_cmdline_facts_name_exact_required_tokens \
	test_cmdline_facts_distinguish_missing_invalid_and_duplicate_tokens \
	test_cmdline_facts_reject_correct_plus_wrong_named_duplicates \
	test_root_device_facts_bind_all_three_canonical_devices \
	test_root_device_facts_reject_unmeasurable_identity \
	test_root_device_facts_reject_nonblock_or_wrong_capacity \
	test_f2fs_probe_exports_norecovery_proof_only_after_clean_unmount \
	test_failed_f2fs_unmount_never_exports_safe_probe_facts \
	test_rootfs_mount_facts_record_unique_mounted_row \
	test_rootfs_mount_facts_reject_missing_or_duplicate_rows; do
	run_test "$test_name"
done

[ "$failures" -eq 0 ] || exit 1
printf 'handoff_semantics=pass\n'
