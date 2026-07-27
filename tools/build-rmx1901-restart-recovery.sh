#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ "$#" -ne 1 ]; then
	printf 'usage: %s OUTPUT\n' "${0##*/}" >&2
	exit 64
fi

output=$1
output_dir=$(dirname -- "$output")
mkdir -p "$output_dir"

exec aarch64-linux-gnu-gcc \
	-nostdlib \
	-static \
	-Os \
	-ffreestanding \
	-fno-stack-protector \
	-Wl,--build-id=none \
	-o "$output" \
	"$PROJECT_ROOT/tools/rmx1901-restart-recovery.c"
