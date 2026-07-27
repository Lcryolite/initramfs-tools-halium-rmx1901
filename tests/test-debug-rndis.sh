#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
POLICY=${RMX1901_DEBUG_POLICY_UNDER_TEST:-$PROJECT_ROOT/scripts/halium-rmx1901-debug}
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rmx1901-debug-rndis.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
	printf 'not ok - %s\n' "$1" >&2
	exit 1
}

[ -f "$POLICY" ] || fail "debug policy missing: $POLICY"
# shellcheck disable=SC1090
. "$POLICY"

rmx1901_debug_requested 'console=tty0 rmx1901.debug_rndis=1' ||
	fail 'one exact debug token was rejected'
for cmdline in \
	'console=tty0' \
	'rmx1901.debug_rndis=0' \
	'rmx1901.debug_rndis=1 rmx1901.debug_rndis=1' \
	'rmx1901.debug_rndis=*' \
	'rmx1901.debug_rndis=1;reboot'; do
	if rmx1901_debug_requested "$cmdline"; then
		fail "unsafe debug command line was accepted: $cmdline"
	fi
done

FAKE_ROOT=$TEST_ROOT/root
FAKE_GADGET=$TEST_ROOT/config/usb_gadget
FAKE_UDC=$TEST_ROOT/sys/class/udc
FAKE_NET=$TEST_ROOT/sys/class/net
FAKE_RUNTIME=$TEST_ROOT/runtime
FAKE_BIN=$TEST_ROOT/bin
CALL_LOG=$TEST_ROOT/calls
mkdir -p \
	"$FAKE_ROOT/usr/lib/systemd/system" \
	"$FAKE_ROOT/opt/halium-overlay/etc/ssh/authorized_keys" \
	"$FAKE_ROOT/var/lib/extrausers" \
	"$FAKE_ROOT/run" \
	"$FAKE_GADGET" "$FAKE_UDC/a600000.dwc3" "$FAKE_NET/rndis0" \
	"$FAKE_RUNTIME" "$FAKE_BIN"
: >"$FAKE_ROOT/usr/lib/systemd/system/usb-moded.service"
: >"$FAKE_ROOT/opt/halium-overlay/etc/ssh/authorized_keys/rmx1901-ut-debug"
printf 'phablet:x:32011:32011:phablet:/home/phablet:/bin/bash\n' \
	>"$FAKE_ROOT/var/lib/extrausers/passwd"
: >"$CALL_LOG"

for root_tool in \
	/bin/sh /bin/busybox /bin/rm /bin/rmdir /bin/readlink \
	/usr/bin/setsid /usr/bin/ssh-keygen /usr/sbin/sshd; do
	mkdir -p "$FAKE_ROOT${root_tool%/*}"
	: >"$FAKE_ROOT$root_tool"
	chmod 0755 "$FAKE_ROOT$root_tool"
done

for command_name in ifconfig chroot; do
	sed "s/@COMMAND@/$command_name/g" >"$FAKE_BIN/$command_name" <<'EOF'
#!/bin/sh
printf '@COMMAND@' >>"$CALL_LOG"
printf ' %s' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"
if [ '@COMMAND@' = ifconfig ] && [ "${FAIL_IFCONFIG:-0}" = 1 ] && [ "${2:-}" != down ]; then
	exit 77
fi
EOF
	chmod 0755 "$FAKE_BIN/$command_name"
done
cat >"$FAKE_BIN/mkdir" <<'EOF'
#!/bin/sh
if [ "${FAIL_PRIMARY_RNDIS:-0}" = 1 ] && [ "${1:-}" = "$RMX1901_GADGET_DIR/g1/functions/rndis.usb0" ]; then
  exit 77
fi
exec /bin/mkdir "$@"
EOF
chmod 0755 "$FAKE_BIN/mkdir"
printf 'sleep 5\n' >>"$FAKE_BIN/chroot"

PATH="$FAKE_BIN:$PATH"
export PATH CALL_LOG
RMX1901_GADGET_DIR=$FAKE_GADGET
RMX1901_UDC_DIR=$FAKE_UDC
RMX1901_NET_DIR=$FAKE_NET
RMX1901_RUNTIME_DIR=$FAKE_RUNTIME
export RMX1901_GADGET_DIR RMX1901_UDC_DIR RMX1901_NET_DIR RMX1901_RUNTIME_DIR

rmx1901_enable_debug_bridge "$FAKE_ROOT" || fail 'debug bridge fixture failed'

[ "$(readlink "$FAKE_RUNTIME/systemd/system/usb-moded.service")" = /dev/null ] ||
	fail 'usb-moded was not transiently runtime-masked'
grep -Fxq 'ifconfig rndis0 192.168.2.15 netmask 255.255.255.0 up' \
	"$CALL_LOG" || fail 'known debug address was not assigned'
[ "$(cat "$FAKE_GADGET/g1/idVendor")" = 0x18D1 ] || fail 'wrong gadget VID'
[ "$(cat "$FAKE_GADGET/g1/idProduct")" = 0xD001 ] || fail 'wrong gadget PID'
[ "$(cat "$FAKE_GADGET/g1/UDC")" = a600000.dwc3 ] || fail 'wrong UDC binding'
[ -L "$FAKE_GADGET/g1/configs/c.1/rndis.usb0" ] || fail 'rndis function is not linked'
[ ! -e "$FAKE_GADGET/g1/configs/c.1/rndis_bam.rndis" ] || fail 'fallback RNDIS function must not be linked with primary'
[ "$(grep -c '^chroot ' "$CALL_LOG")" -eq 1 ] || fail 'rootfs helper launch count is wrong'
grep -Fq 'PasswordAuthentication=no' "$CALL_LOG" || fail 'password authentication is not disabled'
grep -Fq 'AuthenticationMethods=publickey' "$CALL_LOG" || fail 'public-key-only policy is missing'
grep -Fq 'PermitRootLogin=no' "$CALL_LOG" || fail 'root login is not disabled'
grep -Fq -- '-f /dev/null' "$CALL_LOG" || fail 'host ssh configuration was not isolated'
grep -Fq 'UseDNS=no' "$CALL_LOG" || fail 'reverse DNS lookup is not disabled'
grep -Fq 'trap debug_inner_cleanup 0 1 2 3 15' "$CALL_LOG" ||
	fail 'post-handoff helper cleanup trap is missing'
grep -Fq 'AuthorizedKeysFile=/opt/halium-overlay/etc/ssh/authorized_keys/rmx1901-ut-debug' \
	"$CALL_LOG" || fail 'immutable authorized key is not used'
kill "$dbg_helper_pid" 2>/dev/null || true
wait "$dbg_helper_pid" 2>/dev/null || true

rm -rf "$FAKE_GADGET/g1"
rm -f "$FAKE_RUNTIME/systemd/system/usb-moded.service" \
	"$FAKE_RUNTIME/rmx1901-debug-handoff"
FAIL_PRIMARY_RNDIS=1
export FAIL_PRIMARY_RNDIS
rmx1901_enable_debug_bridge "$FAKE_ROOT" || fail 'RNDIS fallback bridge fixture failed'
[ -L "$FAKE_GADGET/g1/configs/c.1/rndis_bam.rndis" ] || fail 'fallback RNDIS function is not linked'
[ ! -e "$FAKE_GADGET/g1/configs/c.1/rndis.usb0" ] || fail 'failed primary RNDIS function leaked'
kill "$dbg_helper_pid" 2>/dev/null || true
wait "$dbg_helper_pid" 2>/dev/null || true
unset FAIL_PRIMARY_RNDIS

rm -rf "$FAKE_GADGET/g1"
rm -f "$FAKE_RUNTIME/systemd/system/usb-moded.service" \
	"$FAKE_RUNTIME/rmx1901-debug-handoff"
FAIL_IFCONFIG=1
export FAIL_IFCONFIG
if rmx1901_enable_debug_bridge "$FAKE_ROOT"; then
	fail 'post-UDC interface failure was accepted'
fi
[ ! -e "$FAKE_GADGET/g1" ] || fail 'failed bridge left a bound gadget tree'
[ ! -e "$FAKE_RUNTIME/systemd/system/usb-moded.service" ] ||
	fail 'failed bridge left the runtime usb-moded mask'
[ ! -e "$FAKE_RUNTIME/rmx1901-debug-handoff" ] ||
	fail 'failed bridge left the handoff marker'

if grep -Eq 'PasswordAuthentication=yes|PermitEmptyPasswords=yes|PermitRootLogin=yes|/userdata/|mkfs|fsck|format|wipe' "$POLICY"; then
	fail 'debug policy contains a forbidden persistence or authentication path'
fi
grep -Fq 'mount -t configfs none /sys/kernel/config' "$POLICY" ||
	fail 'normal-boot configfs mount is missing'

printf 'ok - command-line-gated public-key-only diagnostic RNDIS bridge\n'
