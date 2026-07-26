#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$PROJECT_ROOT/tools/archive-lib.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rmx1901-archive-errors.XXXXXX")
trap 'chmod -R u+rwX "$TEST_ROOT" 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

command -v pack_initrd >/dev/null 2>&1 || fail "checked pack_initrd function is missing"

printf 'not a gzip stream\n' >"$TEST_ROOT/corrupt.img"
if extract_initrd "$TEST_ROOT/corrupt.img" "$TEST_ROOT/corrupt-out" 2>/dev/null; then
	fail "corrupt gzip input was accepted"
fi

mkdir -p "$TEST_ROOT/unreadable-root"
printf 'must not be silently omitted\n' >"$TEST_ROOT/unreadable-root/secret"
chmod 000 "$TEST_ROOT/unreadable-root/secret"
if pack_initrd "$TEST_ROOT/unreadable-root" "$TEST_ROOT/incomplete.img" 2>/dev/null; then
	fail "cpio read failure was hidden by gzip"
fi

if manifest_tree "$TEST_ROOT/does-not-exist" "$TEST_ROOT/nonexistent.manifest" 2>/dev/null; then
	fail "manifest generation ignored an invalid root"
fi
if manifest_tree "$TEST_ROOT/unreadable-root" "$TEST_ROOT/unreadable.manifest" 2>/dev/null; then
	fail "manifest generation hid a file hash failure"
fi

printf 'ok - gzip/cpio failures propagate instead of producing trusted output\n'
