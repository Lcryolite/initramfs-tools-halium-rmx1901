#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rmx1901-spec-order.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
GATE=$PROJECT_ROOT/tools/check-m1-spec-order.sh
MARKER=$PROJECT_ROOT/config/m1-event-order-contract.env

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

cat >"$TEST_ROOT/aligned.md" <<'EOF'
## 9. Initramfs observation contract
1. `CMDLINE_PARSED`
2. `ROOT_DEVICE_RESOLVED`
3. `USERDATA_PROBED`
4. `ROOTFS_MOUNTED`
5. `DEV_MOVE_BEGIN` / `DEV_MOVE_DONE`
## 10. Next section
EOF

cat >"$TEST_ROOT/diverged.md" <<'EOF'
## 9. Initramfs observation contract
1. `CMDLINE_PARSED`
2. `ROOT_DEVICE_RESOLVED`
3. `ROOTFS_MOUNTED`
4. `USERDATA_PROBED`
5. `DEV_MOVE_BEGIN` / `DEV_MOVE_DONE`
## 10. Next section
EOF

[ -x "$GATE" ] || fail 'M1 spec order gate is missing or not executable'
[ -f "$MARKER" ] || fail 'M1 source order contract marker is missing'
if "$GATE" "$TEST_ROOT/diverged.md" >"$TEST_ROOT/diverged.out" 2>"$TEST_ROOT/diverged.err"; then
	fail 'gate accepted the old noncausal spec order'
else
	status=$?
fi
[ "$status" -eq 20 ] || fail 'spec divergence did not use evidence failure exit 20'
grep -Fxq 'M1_SPEC_ALIGNMENT=BLOCKED' "$TEST_ROOT/diverged.out" ||
	fail 'spec divergence has no formal BLOCKED marker'
"$GATE" "$TEST_ROOT/aligned.md" >"$TEST_ROOT/aligned.out"
grep -Fxq 'M1_SPEC_ALIGNMENT=PASS' "$TEST_ROOT/aligned.out" ||
	fail 'causal source/spec alignment did not pass'

cp "$PROJECT_ROOT/scripts/halium" "$TEST_ROOT/halium-missing"
sed -i '/rmx1901_handoff_event USERDATA_PROBED /d' "$TEST_ROOT/halium-missing"
if "$GATE" "$TEST_ROOT/aligned.md" "$TEST_ROOT/halium-missing" \
	>"$TEST_ROOT/missing.out" 2>"$TEST_ROOT/missing.err"; then
	fail 'gate accepted a source with a missing emitted stage'
fi
grep -Fxq 'M1_SPEC_ALIGNMENT=BLOCKED' "$TEST_ROOT/missing.out" ||
	fail 'missing source stage has no formal BLOCKED result'

sed \
	-e 's/rmx1901_handoff_event USERDATA_PROBED /rmx1901_handoff_event TEMP_STAGE /' \
	-e 's/rmx1901_handoff_event ROOTFS_MOUNTED /rmx1901_handoff_event USERDATA_PROBED /' \
	-e 's/rmx1901_handoff_event TEMP_STAGE /rmx1901_handoff_event ROOTFS_MOUNTED /' \
	"$PROJECT_ROOT/scripts/halium" >"$TEST_ROOT/halium-reordered"
if "$GATE" "$TEST_ROOT/aligned.md" "$TEST_ROOT/halium-reordered" \
	>"$TEST_ROOT/reordered.out" 2>"$TEST_ROOT/reordered.err"; then
	fail 'gate accepted reordered source emission calls'
fi
grep -Fxq 'M1_SPEC_ALIGNMENT=BLOCKED' "$TEST_ROOT/reordered.out" ||
	fail 'reordered source stages have no formal BLOCKED result'

make_build_gate_fixture() {
	fixture_name=$1
	fixture_source=$2
	fixture_root=$TEST_ROOT/$fixture_name
	mkdir -p "$fixture_root/tools" "$fixture_root/scripts" "$fixture_root/config" "$fixture_root/patches"
	cp "$PROJECT_ROOT/tools/derive-initrd.sh" "$fixture_root/tools/derive-initrd.sh"
	cp "$PROJECT_ROOT/tools/audit-initrd.sh" "$fixture_root/tools/audit-initrd.sh"
	cp "$PROJECT_ROOT/tools/check-m1-spec-order.sh" "$fixture_root/tools/check-m1-spec-order.sh"
	cp "$PROJECT_ROOT/tools/archive-lib.sh" "$fixture_root/tools/archive-lib.sh"
	cp "$PROJECT_ROOT/tools/snapshot-regular-file.py" "$fixture_root/tools/snapshot-regular-file.py"
	cp "$fixture_source" "$fixture_root/scripts/halium"
	cp "$PROJECT_ROOT/config/m1-event-order-contract.env" "$fixture_root/config/m1-event-order-contract.env"
	cp "$TEST_ROOT/aligned.md" "$fixture_root/config/m1-event-order-spec.md"
	cp "$PROJECT_ROOT/patches/0001-rmx1901-record-base-init-handoff-events.patch" \
		"$fixture_root/patches/0001-rmx1901-record-base-init-handoff-events.patch"
}

make_build_gate_fixture gate-missing "$TEST_ROOT/halium-missing"
make_build_gate_fixture gate-reordered "$TEST_ROOT/halium-reordered"
for fixture_name in gate-missing gate-reordered; do
	fixture_root=$TEST_ROOT/$fixture_name
	if "$fixture_root/tools/derive-initrd.sh" "$TEST_ROOT/nonexistent-base" "$TEST_ROOT/${fixture_name}-out" \
		>"$TEST_ROOT/${fixture_name}-derive.out" 2>"$TEST_ROOT/${fixture_name}-derive.err"; then
		fail "derive accepted $fixture_name source emission"
	fi
	grep -Fq 'M1 source/spec order gate failed' "$TEST_ROOT/${fixture_name}-derive.err" ||
		fail "derive did not fail at source/spec gate for $fixture_name"
	if "$fixture_root/tools/audit-initrd.sh" \
		"$TEST_ROOT/nonexistent-base" "$TEST_ROOT/nonexistent-derived" \
		"$TEST_ROOT/nonexistent-before" "$TEST_ROOT/nonexistent-after" \
		>"$TEST_ROOT/${fixture_name}-audit.out" 2>"$TEST_ROOT/${fixture_name}-audit.err"; then
		fail "audit accepted $fixture_name source emission"
	fi
	grep -Fq 'M1 source/spec order gate failed' "$TEST_ROOT/${fixture_name}-audit.err" ||
		fail "audit did not fail at source/spec gate for $fixture_name"
done

printf 'ok - formal M1 source/spec event-order alignment gate\n'
