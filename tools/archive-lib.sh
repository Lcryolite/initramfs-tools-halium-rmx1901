#!/bin/sh

manifest_tree() {
	manifest_root=$1
	manifest_output=$2
	manifest_work=$(mktemp -d "${TMPDIR:-/tmp}/rmx1901-initrd-manifest.XXXXXX")
	if ! (cd "$manifest_root" && find . -mindepth 1 -printf '%P\n' >"$manifest_work/paths.unsorted"); then
		rm -rf "$manifest_work"
		return 1
	fi
	if ! LC_ALL=C sort "$manifest_work/paths.unsorted" >"$manifest_work/paths.sorted"; then
		rm -rf "$manifest_work"
		return 1
	fi
	: >"$manifest_work/manifest"
	while IFS= read -r manifest_path; do
		case "$manifest_path" in
			*' '*|*'	'*)
				printf 'unsupported whitespace in archive path: %s\n' "$manifest_path" >&2
				rm -rf "$manifest_work"
				return 1
				;;
		esac
		if [ -L "$manifest_root/$manifest_path" ]; then
			manifest_type=symlink
			if ! manifest_target=$(readlink "$manifest_root/$manifest_path"); then
				rm -rf "$manifest_work"
				return 1
			fi
			manifest_size=$(printf '%s' "$manifest_target" | wc -c) || {
				rm -rf "$manifest_work"
				return 1
			}
			manifest_hash=$(printf '%s' "$manifest_target" | sha256sum | awk '{print $1}') || {
				rm -rf "$manifest_work"
				return 1
			}
		elif [ -f "$manifest_root/$manifest_path" ]; then
			manifest_type=file
			manifest_size=$(stat -c %s "$manifest_root/$manifest_path") || {
				rm -rf "$manifest_work"
				return 1
			}
			manifest_hash_line=$(sha256sum "$manifest_root/$manifest_path") || {
				rm -rf "$manifest_work"
				return 1
			}
			manifest_hash=${manifest_hash_line%% *}
		elif [ -d "$manifest_root/$manifest_path" ]; then
			manifest_type=directory
			manifest_size=0
			manifest_hash=-
		else
			manifest_type=special
			manifest_size=0
			manifest_hash=-
		fi
		manifest_mode=$(stat -c %a "$manifest_root/$manifest_path") || {
			rm -rf "$manifest_work"
			return 1
		}
		if ! printf '%s %s %s %s %s\n' \
			"$manifest_hash" "$manifest_type" "$manifest_mode" "$manifest_size" "$manifest_path" \
			>>"$manifest_work/manifest"; then
			rm -rf "$manifest_work"
			return 1
		fi
	done <"$manifest_work/paths.sorted"
	if ! mv "$manifest_work/manifest" "$manifest_output"; then
		rm -rf "$manifest_work"
		return 1
	fi
	rm -rf "$manifest_work"
}

extract_initrd() {
	archive=$1
	destination=$2
	compressed_stream=$(mktemp "${TMPDIR:-/tmp}/rmx1901-initrd-extract.XXXXXX")
	mkdir -p "$destination"
	if ! gzip -dc "$archive" >"$compressed_stream"; then
		rm -f "$compressed_stream"
		return 1
	fi
	if ! (
		cd "$destination"
		cpio -idm --no-absolute-filenames --preserve-modification-time \
			<"$compressed_stream" 2>"$compressed_stream.stderr"
	); then
		cat "$compressed_stream.stderr" >&2
		rm -f "$compressed_stream"
		rm -f "$compressed_stream.stderr"
		return 1
	fi
	rm -f "$compressed_stream"
	rm -f "$compressed_stream.stderr"
}

pack_initrd() {
	pack_root=$1
	pack_output=$2
	pack_work=$(mktemp -d "${TMPDIR:-/tmp}/rmx1901-initrd-pack.XXXXXX")
	if ! (cd "$pack_root" && find . -print0 >"$pack_work/paths.unsorted"); then
		rm -rf "$pack_work"
		return 1
	fi
	if ! LC_ALL=C sort -z "$pack_work/paths.unsorted" >"$pack_work/paths.sorted"; then
		rm -rf "$pack_work"
		return 1
	fi
	if ! (
		cd "$pack_root"
		cpio --null -o -H newc --reproducible --owner=0:0 \
			<"$pack_work/paths.sorted" >"$pack_work/archive.cpio" 2>"$pack_work/cpio.stderr"
	); then
		cat "$pack_work/cpio.stderr" >&2
		rm -rf "$pack_work"
		return 1
	fi
	if ! gzip -n -9 <"$pack_work/archive.cpio" >"$pack_output"; then
		rm -rf "$pack_work"
		return 1
	fi
	rm -rf "$pack_work"
}

write_delta_manifest() {
	before_manifest=$1
	after_manifest=$2
	delta_output=$3
	awk '
		NR == FNR { before[$5] = $0; next }
		{
			after[$5] = $0
			if (!($5 in before)) print "ADD " $5
			else if (before[$5] != $0) print "REPLACE " $5
		}
		END {
			for (path in before)
				if (!(path in after)) print "DELETE " path
		}
	' "$before_manifest" "$after_manifest" | LC_ALL=C sort >"$delta_output"
}
