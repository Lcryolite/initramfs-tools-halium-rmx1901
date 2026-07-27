#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$PROJECT_ROOT/tools/archive-lib.sh"

BASE_IMAGE=${1:?usage: derive-initrd.sh BASE_IMAGE OUTPUT_DIRECTORY}
OUTPUT_DIRECTORY=${2:?usage: derive-initrd.sh BASE_IMAGE OUTPUT_DIRECTORY}
PINNED_BASE_SHA=0bbac4577f3567aec935c958216de5d30c7355452ca56248d6728f4f2634bdb6
FIXED_SOURCE_DATE_EPOCH=1673963166
ARTIFACT_NAME=initrd.img-touch-arm64-rmx1901-safe
BASE_INIT_PATCH=$PROJECT_ROOT/patches/0001-rmx1901-record-base-init-handoff-events.patch
BASE_SNAPSHOT_TOOL=$PROJECT_ROOT/tools/snapshot-regular-file.py
M1_SPEC_ORDER_GATE=$PROJECT_ROOT/tools/check-m1-spec-order.sh
M1_SPEC_ORDER_SPEC=$PROJECT_ROOT/config/m1-event-order-spec.md
RECOVERY_HELPER_BUILDER=$PROJECT_ROOT/tools/build-rmx1901-restart-recovery.sh

if ! "$M1_SPEC_ORDER_GATE" "$M1_SPEC_ORDER_SPEC"; then
	printf 'M1 source/spec order gate failed\n' >&2
	exit 20
fi

if [ -e "$OUTPUT_DIRECTORY" ] && [ -n "$(find "$OUTPUT_DIRECTORY" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
	printf 'output directory must be absent or empty: %s\n' "$OUTPUT_DIRECTORY" >&2
	exit 1
fi
mkdir -p "$OUTPUT_DIRECTORY"
OUTPUT_DIRECTORY=$(CDPATH= cd -- "$OUTPUT_DIRECTORY" && pwd)

BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rmx1901-initrd-build.XXXXXX")
trap 'rm -rf "$BUILD_ROOT"' EXIT HUP INT TERM
BASE_SNAPSHOT=$BUILD_ROOT/base.snapshot
"$BASE_SNAPSHOT_TOOL" "$BASE_IMAGE" "$BASE_SNAPSHOT"
actual_base_sha=$(sha256sum "$BASE_SNAPSHOT" | awk '{print $1}')
if [ "$actual_base_sha" != "$PINNED_BASE_SHA" ]; then
	printf 'base initrd SHA-256 mismatch: expected %s, got %s\n' "$PINNED_BASE_SHA" "$actual_base_sha" >&2
	exit 1
fi
UNPACKED=$BUILD_ROOT/unpacked
extract_initrd "$BASE_SNAPSHOT" "$UNPACKED"

manifest_tree "$UNPACKED" "$OUTPUT_DIRECTORY/initrd.before.manifest"

test -f "$BASE_INIT_PATCH" || {
	printf 'RMX1901 base-init handoff patch is missing: %s\n' "$BASE_INIT_PATCH" >&2
	exit 1
}
(cd "$UNPACKED" && patch --batch --fuzz=0 -p1 <"$BASE_INIT_PATCH") || {
	printf 'RMX1901 base-init handoff patch did not apply to the pinned base\n' >&2
	exit 1
}

install -m 0644 "$PROJECT_ROOT/scripts/halium" "$UNPACKED/scripts/halium"
install -m 0644 "$PROJECT_ROOT/scripts/halium-userdata" "$UNPACKED/scripts/halium-userdata"
install -m 0644 "$PROJECT_ROOT/scripts/halium-rmx1901-debug" "$UNPACKED/scripts/halium-rmx1901-debug"
test -x "$RECOVERY_HELPER_BUILDER" || {
	printf 'RMX1901 recovery helper builder is missing: %s\n' "$RECOVERY_HELPER_BUILDER" >&2
	exit 1
}
RECOVERY_HELPER=$BUILD_ROOT/rmx1901-restart-recovery
"$RECOVERY_HELPER_BUILDER" "$RECOVERY_HELPER"
install -m 0755 "$RECOVERY_HELPER" "$UNPACKED/sbin/rmx1901-restart-recovery"
rm -f \
	"$UNPACKED/sbin/e2fsck" \
	"$UNPACKED/sbin/resize2fs" \
	"$UNPACKED/sbin/dumpe2fs"

# File content and modes change only for allowlisted paths. Directory mtimes
# are normalized because GNU cpio extraction updates them while creating
# children, otherwise identical inputs produce different output bytes.
find "$UNPACKED" -type d -exec touch -h -d "@$FIXED_SOURCE_DATE_EPOCH" {} +
touch -h -d "@$FIXED_SOURCE_DATE_EPOCH" \
	"$UNPACKED/init" \
	"$UNPACKED/scripts/halium" \
	"$UNPACKED/scripts/halium-userdata" \
	"$UNPACKED/scripts/halium-rmx1901-debug" \
	"$UNPACKED/sbin/rmx1901-restart-recovery"

manifest_tree "$UNPACKED" "$OUTPUT_DIRECTORY/initrd.after.manifest"
write_delta_manifest \
	"$OUTPUT_DIRECTORY/initrd.before.manifest" \
	"$OUTPUT_DIRECTORY/initrd.after.manifest" \
	"$OUTPUT_DIRECTORY/initrd.delta.manifest"

expected_delta='ADD sbin/rmx1901-restart-recovery
ADD scripts/halium-rmx1901-debug
ADD scripts/halium-userdata
DELETE sbin/dumpe2fs
DELETE sbin/e2fsck
DELETE sbin/resize2fs
REPLACE init
REPLACE scripts/halium'
actual_delta=$(cat "$OUTPUT_DIRECTORY/initrd.delta.manifest")
if [ "$actual_delta" != "$expected_delta" ]; then
	printf 'refusing non-allowlisted archive delta:\n%s\n' "$actual_delta" >&2
	exit 1
fi

pack_initrd "$UNPACKED" "$OUTPUT_DIRECTORY/$ARTIFACT_NAME"

artifact_sha=$(sha256sum "$OUTPUT_DIRECTORY/$ARTIFACT_NAME" | awk '{print $1}')
artifact_size=$(stat -c %s "$OUTPUT_DIRECTORY/$ARTIFACT_NAME")
printf '%s  %s\n' "$artifact_sha" "$ARTIFACT_NAME" >"$OUTPUT_DIRECTORY/$ARTIFACT_NAME.sha256"
created=$(date -u -d "@$FIXED_SOURCE_DATE_EPOCH" '+%Y-%m-%dT%H:%M:%SZ')

cat >"$OUTPUT_DIRECTORY/initrd.spdx.json" <<EOF
{
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "RMX1901-safe-Halium-initrd",
  "documentNamespace": "https://github.com/Lcryolite/initramfs-tools-halium-rmx1901/spdx/$artifact_sha",
  "creationInfo": {
    "created": "$created",
    "creators": ["Tool: tools/derive-initrd.sh"]
  },
  "packages": [{
    "name": "$ARTIFACT_NAME",
    "SPDXID": "SPDXRef-Package-initrd",
    "versionInfo": "rmx1901-safe-debug-v1",
    "downloadLocation": "NOASSERTION",
    "filesAnalyzed": false,
    "checksums": [{"algorithm": "SHA256", "checksumValue": "$artifact_sha"}],
    "copyrightText": "NOASSERTION",
    "comment": "Derived from pinned base SHA256 $actual_base_sha; size $artifact_size bytes. See manifests and PROVENANCE.md."
  }],
  "relationships": [{
    "spdxElementId": "SPDXRef-DOCUMENT",
    "relationshipType": "DESCRIBES",
    "relatedSpdxElement": "SPDXRef-Package-initrd"
  }]
}
EOF
