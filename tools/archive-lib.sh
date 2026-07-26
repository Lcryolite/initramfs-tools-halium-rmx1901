#!/bin/sh

manifest_tree() {
	manifest_root=$1
	manifest_output=$2
	(
		cd "$manifest_root"
		find . -mindepth 1 -printf '%P\n' | LC_ALL=C sort | while IFS= read -r manifest_path; do
			case "$manifest_path" in
				*' '*|*'	'*)
					printf 'unsupported whitespace in archive path: %s\n' "$manifest_path" >&2
					exit 1
					;;
			esac
			if [ -L "$manifest_path" ]; then
				manifest_type=symlink
				manifest_size=$(printf '%s' "$(readlink "$manifest_path")" | wc -c)
				manifest_hash=$(printf '%s' "$(readlink "$manifest_path")" | sha256sum | awk '{print $1}')
			elif [ -f "$manifest_path" ]; then
				manifest_type=file
				manifest_size=$(stat -c %s "$manifest_path")
				manifest_hash=$(sha256sum "$manifest_path" | awk '{print $1}')
			elif [ -d "$manifest_path" ]; then
				manifest_type=directory
				manifest_size=0
				manifest_hash=-
			else
				manifest_type=special
				manifest_size=0
				manifest_hash=-
			fi
			manifest_mode=$(stat -c %a "$manifest_path")
			printf '%s %s %s %s %s\n' "$manifest_hash" "$manifest_type" "$manifest_mode" "$manifest_size" "$manifest_path"
		done
	) >"$manifest_output"
}

extract_initrd() {
	archive=$1
	destination=$2
	mkdir -p "$destination"
	(
		cd "$destination"
		gzip -dc "$archive" | cpio -idm --no-absolute-filenames --preserve-modification-time 2>/dev/null
	)
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
