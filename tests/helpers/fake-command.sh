#!/bin/sh
set -eu

name=${0##*/}

record() {
	line=$name
	for argument in "$@"; do
		line="$line|$argument"
	done
	printf '%s\n' "$line" >>"$CALL_LOG"
}

case "$name" in
	blkid)
		record "$@"
		printf '%s\n' "${BLKID_OUTPUT-}"
		;;
	mount)
		record "$@"
		case " $* " in
			*" -o ro,noload "*|*" -o ro "*)
				if [ "${FAIL_RO-0}" = 1 ]; then exit 1; fi
				;;
			*" -o rw,noatime "*)
				if [ "${FAIL_RW-0}" = 1 ]; then exit 1; fi
				;;
		esac
		;;
	umount)
		record "$@"
		if [ "${FAIL_UMOUNT-0}" = 1 ]; then exit 1; fi
		;;
	is-block)
		record "$@"
		[ "${IS_BLOCK-1}" = 1 ]
		;;
	has-payload)
		record "$@"
		[ "${HAS_PAYLOAD-1}" = 1 ]
		;;
	canonical-path)
		record "$@"
		printf '%s\n' "${CANONICAL_PATH-}"
		;;
	log|panic)
		record "$@"
		;;
	*)
		printf 'unknown fake command: %s\n' "$name" >&2
		exit 2
		;;
esac
