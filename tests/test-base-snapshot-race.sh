#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rmx1901-base-race.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
PINNED_BASE_IMAGE=${PINNED_BASE_IMAGE:-/var/tmp/rmx1901-halium-initrd-cache/92015679-0bbac4577f3567aec935c958216de5d30c7355452ca56248d6728f4f2634bdb6-initrd.img-touch-arm64}
REAL_SHA256SUM=$(command -v sha256sum)

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

[ -f "$PINNED_BASE_IMAGE" ] || fail "pinned base fixture unavailable: $PINNED_BASE_IMAGE"
mkdir "$TEST_ROOT/fake-bin"
cat >"$TEST_ROOT/fake-bin/sha256sum" <<'EOF'
#!/bin/sh
"$REAL_SHA256SUM" "$@"
status=$?
if [ "$status" -eq 0 ] && [ -n "${RACE_TARGET-}" ] && [ ! -e "$RACE_MARKER" ]; then
	mv "$RACE_REPLACEMENT" "$RACE_TARGET"
	: >"$RACE_MARKER"
fi
exit "$status"
EOF
chmod +x "$TEST_ROOT/fake-bin/sha256sum"

"$PROJECT_ROOT/tools/derive-initrd.sh" "$PINNED_BASE_IMAGE" "$TEST_ROOT/reference"

cp "$PINNED_BASE_IMAGE" "$TEST_ROOT/racy-derive.img"
printf 'replacement after hash\n' >"$TEST_ROOT/derive-replacement.img"
REAL_SHA256SUM=$REAL_SHA256SUM \
RACE_TARGET=$TEST_ROOT/racy-derive.img \
RACE_REPLACEMENT=$TEST_ROOT/derive-replacement.img \
RACE_MARKER=$TEST_ROOT/derive-raced \
PATH=$TEST_ROOT/fake-bin:$PATH \
	"$PROJECT_ROOT/tools/derive-initrd.sh" "$TEST_ROOT/racy-derive.img" "$TEST_ROOT/raced"
[ -e "$TEST_ROOT/derive-raced" ] || fail 'derive hash-to-extract replacement hook did not run'
cmp "$TEST_ROOT/reference/initrd.img-touch-arm64-rmx1901-safe" \
	"$TEST_ROOT/raced/initrd.img-touch-arm64-rmx1901-safe" ||
	fail 'derive output consumed the replaced caller path instead of its private snapshot'

cp "$PINNED_BASE_IMAGE" "$TEST_ROOT/racy-audit.img"
printf 'replacement after hash\n' >"$TEST_ROOT/audit-replacement.img"
REAL_SHA256SUM=$REAL_SHA256SUM \
RACE_TARGET=$TEST_ROOT/racy-audit.img \
RACE_REPLACEMENT=$TEST_ROOT/audit-replacement.img \
RACE_MARKER=$TEST_ROOT/audit-raced \
PATH=$TEST_ROOT/fake-bin:$PATH \
	"$PROJECT_ROOT/tools/audit-initrd.sh" \
	"$TEST_ROOT/racy-audit.img" \
	"$TEST_ROOT/reference/initrd.img-touch-arm64-rmx1901-safe" \
	"$TEST_ROOT/reference/initrd.before.manifest" \
	"$TEST_ROOT/reference/initrd.after.manifest"
[ -e "$TEST_ROOT/audit-raced" ] || fail 'audit hash-to-extract replacement hook did not run'

cp "$TEST_ROOT/reference/initrd.img-touch-arm64-rmx1901-safe" "$TEST_ROOT/racy-derived.img"
printf 'replacement after input snapshot\n' >"$TEST_ROOT/derived-replacement.img"
REAL_SHA256SUM=$REAL_SHA256SUM \
RACE_TARGET=$TEST_ROOT/racy-derived.img \
RACE_REPLACEMENT=$TEST_ROOT/derived-replacement.img \
RACE_MARKER=$TEST_ROOT/derived-raced \
PATH=$TEST_ROOT/fake-bin:$PATH \
	"$PROJECT_ROOT/tools/audit-initrd.sh" \
	"$PINNED_BASE_IMAGE" \
	"$TEST_ROOT/racy-derived.img" \
	"$TEST_ROOT/reference/initrd.before.manifest" \
	"$TEST_ROOT/reference/initrd.after.manifest"
[ -e "$TEST_ROOT/derived-raced" ] || fail 'derived path replacement hook did not run'

for manifest_kind in before after; do
	cp "$TEST_ROOT/reference/initrd.${manifest_kind}.manifest" "$TEST_ROOT/racy-${manifest_kind}.manifest"
	printf 'replacement after input snapshot\n' >"$TEST_ROOT/${manifest_kind}-replacement.manifest"
	before_input=$TEST_ROOT/reference/initrd.before.manifest
	after_input=$TEST_ROOT/reference/initrd.after.manifest
	[ "$manifest_kind" != before ] || before_input=$TEST_ROOT/racy-before.manifest
	[ "$manifest_kind" != after ] || after_input=$TEST_ROOT/racy-after.manifest
	REAL_SHA256SUM=$REAL_SHA256SUM \
	RACE_TARGET=$TEST_ROOT/racy-${manifest_kind}.manifest \
	RACE_REPLACEMENT=$TEST_ROOT/${manifest_kind}-replacement.manifest \
	RACE_MARKER=$TEST_ROOT/${manifest_kind}-raced \
	PATH=$TEST_ROOT/fake-bin:$PATH \
		"$PROJECT_ROOT/tools/audit-initrd.sh" \
		"$PINNED_BASE_IMAGE" \
		"$TEST_ROOT/reference/initrd.img-touch-arm64-rmx1901-safe" \
		"$before_input" "$after_input"
	[ -e "$TEST_ROOT/${manifest_kind}-raced" ] || fail "$manifest_kind manifest replacement hook did not run"
done

ln -s "$TEST_ROOT/reference/initrd.img-touch-arm64-rmx1901-safe" "$TEST_ROOT/derived-symlink.img"
if "$PROJECT_ROOT/tools/audit-initrd.sh" \
	"$PINNED_BASE_IMAGE" "$TEST_ROOT/derived-symlink.img" \
	"$TEST_ROOT/reference/initrd.before.manifest" "$TEST_ROOT/reference/initrd.after.manifest" \
	>"$TEST_ROOT/derived-symlink.stdout" 2>"$TEST_ROOT/derived-symlink.stderr"; then
	fail 'audit accepted a symlink derived image'
fi
grep -Fq 'refusing non-regular or linked snapshot source' "$TEST_ROOT/derived-symlink.stderr" ||
	fail 'derived symlink rejection was not the O_NOFOLLOW snapshot gate'

ln -s "$PINNED_BASE_IMAGE" "$TEST_ROOT/base-symlink.img"
if "$PROJECT_ROOT/tools/derive-initrd.sh" "$TEST_ROOT/base-symlink.img" "$TEST_ROOT/symlink-out" \
	>"$TEST_ROOT/symlink.stdout" 2>"$TEST_ROOT/symlink.stderr"; then
	fail 'derive accepted a symlink base despite the O_NOFOLLOW contract'
fi
grep -Fq 'refusing non-regular or linked snapshot source' "$TEST_ROOT/symlink.stderr" ||
	fail 'symlink rejection was not the O_NOFOLLOW snapshot gate'

printf 'ok - derive/audit use O_NOFOLLOW private input snapshots across hash, extract, and compare\n'
