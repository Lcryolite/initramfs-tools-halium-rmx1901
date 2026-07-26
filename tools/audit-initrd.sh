#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$PROJECT_ROOT/tools/archive-lib.sh"

BASE_IMAGE=${1:?usage: audit-initrd.sh BASE DERIVED BEFORE_MANIFEST AFTER_MANIFEST}
DERIVED_IMAGE=${2:?usage: audit-initrd.sh BASE DERIVED BEFORE_MANIFEST AFTER_MANIFEST}
RECORDED_BEFORE=${3:?usage: audit-initrd.sh BASE DERIVED BEFORE_MANIFEST AFTER_MANIFEST}
RECORDED_AFTER=${4:?usage: audit-initrd.sh BASE DERIVED BEFORE_MANIFEST AFTER_MANIFEST}
BASE_IMAGE=$(readlink -f "$BASE_IMAGE")
DERIVED_IMAGE=$(readlink -f "$DERIVED_IMAGE")
RECORDED_BEFORE=$(readlink -f "$RECORDED_BEFORE")
RECORDED_AFTER=$(readlink -f "$RECORDED_AFTER")

AUDIT_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rmx1901-initrd-audit.XXXXXX")
trap 'rm -rf "$AUDIT_ROOT"' EXIT HUP INT TERM
extract_initrd "$BASE_IMAGE" "$AUDIT_ROOT/base"
extract_initrd "$DERIVED_IMAGE" "$AUDIT_ROOT/derived"
manifest_tree "$AUDIT_ROOT/base" "$AUDIT_ROOT/before.manifest"
manifest_tree "$AUDIT_ROOT/derived" "$AUDIT_ROOT/after.manifest"
cmp "$RECORDED_BEFORE" "$AUDIT_ROOT/before.manifest"
cmp "$RECORDED_AFTER" "$AUDIT_ROOT/after.manifest"

write_delta_manifest "$AUDIT_ROOT/before.manifest" "$AUDIT_ROOT/after.manifest" "$AUDIT_ROOT/delta.manifest"
expected_delta='ADD scripts/halium-userdata
DELETE sbin/dumpe2fs
DELETE sbin/e2fsck
DELETE sbin/resize2fs
REPLACE scripts/halium'
[ "$(cat "$AUDIT_ROOT/delta.manifest")" = "$expected_delta" ] || {
	printf 'audit rejected non-allowlisted delta:\n' >&2
	cat "$AUDIT_ROOT/delta.manifest" >&2
	exit 1
}

for forbidden_tool in e2fsck resize2fs dumpe2fs mke2fs fsck.f2fs fsck.f2fs.static; do
	if [ -e "$AUDIT_ROOT/derived/sbin/$forbidden_tool" ] || [ -e "$AUDIT_ROOT/derived/bin/$forbidden_tool" ]; then
		printf 'forbidden executable remains: %s\n' "$forbidden_tool" >&2
		exit 1
	fi
done

if grep -E '[;&|[:space:]](e2fsck|resize2fs|dumpe2fs|mke2fs|mkfs(\.[^;&|[:space:]]*)?|fsck\.f2fs)([;&|[:space:]]|$)' \
	"$AUDIT_ROOT/derived/scripts/halium" \
	"$AUDIT_ROOT/derived/scripts/halium-userdata"; then
	printf 'forbidden filesystem mutation command appears in boot control path\n' >&2
	exit 1
fi

if grep -E '(^|[,[:space:]])(discard|data=journal)([,[:space:]]|$)' \
	"$AUDIT_ROOT/derived/scripts/halium" \
	"$AUDIT_ROOT/derived/scripts/halium-userdata"; then
	printf 'forbidden userdata mount option appears in boot control path\n' >&2
	exit 1
fi

cmp "$PROJECT_ROOT/scripts/halium" "$AUDIT_ROOT/derived/scripts/halium"
cmp "$PROJECT_ROOT/scripts/halium-userdata" "$AUDIT_ROOT/derived/scripts/halium-userdata"
printf 'audit ok: allowlisted delta only; forbidden tools/commands/options absent\n'
