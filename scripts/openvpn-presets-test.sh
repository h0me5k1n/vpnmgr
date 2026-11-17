#!/bin/sh
# Offline tests of the real preset/toggle functions; never source the dispatcher.
# Production functions consume the fixture globals through the extracted source.
# shellcheck disable=SC2034
set -eu
REPO_ROOT="$(CDPATH='' cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
mkdir -p "$TEST_DIR/openvpn"
TEST_OS="$(uname -s)"
TEST_SED="$(command -v sed)"
TEST_BSD_SED="false"
if [ "$TEST_OS" = "Darwin" ]; then
	if command -v gsed >/dev/null 2>&1; then
		TEST_SED="$(command -v gsed)"
	else
		TEST_BSD_SED="true"
	fi
fi

for test_fn in Validate_Number ParseSlotSelection SetVPNCustomSettings \
	Write_VPNCustomOptions Toggle_VPN_Custom_Settings; do
	sed -n "/^${test_fn}(){/,/^}/p" "$REPO_ROOT/vpnmgr.sh"
done | sed "s|/jffs/openvpn/|\"\$TEST_DIR\"/openvpn/|g" > "$TEST_DIR/functions.sh"
. "$TEST_DIR/functions.sh"

# Use the installed sed implementation. Adapt only BSD sed's -i syntax when
# GNU sed is unavailable; Linux and BusyBox use their native -i behavior.
sed(){
	if [ "$TEST_BSD_SED" = "true" ] && [ "$1" = "-i" ]; then
		"$TEST_SED" -i '' "$2" "$3"
	else
		"$TEST_SED" "$@"
	fi
}

die(){ printf 'FAIL: %s\n' "$*" >&2; exit 1; }
has(){ grep -Fqx "$1" "$2" || die "missing '$1' in $3"; }
lacks(){ if grep -Fqx "$1" "$2"; then die "unexpected '$1' in $3"; fi; }
state_is(){
	_state_actual="$(grep "^vpn${1}_customsettings=" "$SCRIPT_CONF" | cut -d= -f2)"
	[ "$_state_actual" = "$2" ] || die "slot $1 flag expected $2, got $_state_actual"
}
Print_Output(){ printf '%s\n' "$2" >> "$TEST_DIR/messages"; }
Validate_Number(){ case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
Firmware_Build_Before(){ return 1; }
Detect_OpenVPN_Runtime(){
	OVPN_RUNTIME_VERSION="$TEST_RUNTIME_VERSION"
	OVPN_RUNTIME_NUMBER="$TEST_RUNTIME_NUMBER"
	OVPN_RUNTIME_FAMILY="$TEST_RUNTIME_FAMILY"
	OVPN_RUNTIME_STATUS="$TEST_RUNTIME_STATUS"
}

SCRIPT_CONF="$TEST_DIR/config"
PASS="PASS"
WARN="WARN"
ERR="ERR"
cat > "$SCRIPT_CONF" <<'EOF'
vpn1_managed=true
vpn1_customsettings=false
vpn1_provider=NordVPN
vpn1_protocol=UDP
vpn1_mute=20
vpn1_debugverb=false
vpn2_managed=false
vpn2_customsettings=false
vpn2_provider=Surfshark
vpn2_protocol=TCP
vpn2_mute=0
vpn2_debugverb=true
vpn3_managed=true
vpn3_customsettings=true
vpn3_provider=NordVPN
vpn3_protocol=TCP
vpn3_mute=0
vpn3_debugverb=false
vpn4_managed=true
vpn4_customsettings=false
vpn4_provider=Surfshark
vpn4_protocol=UDP
vpn4_mute=
vpn4_debugverb=true
EOF

# 2.5 uses legacy UDP settings and retains persist-key. Caller globals are stale.
VPN_PROVIDER=Surfshark VPN_PROT_SHORT=TCP
SetVPNCustomSettings 1 legacy 2005000 'shaper 1000000'
_options="$TEST_DIR/openvpn/vpn_client1_custom3"
has 'persist-key' "$_options" '2.5 legacy UDP'
has 'explicit-exit-notify 3' "$_options" '2.5 legacy UDP'
has 'tun-mtu 1500' "$_options" '2.5 legacy UDP'
has 'tun-mtu-extra 32' "$_options" '2.5 legacy UDP'
has 'mssfix 1450' "$_options" '2.5 legacy UDP'
lacks 'fast-io' "$_options" 'conservative shaper handling'
lacks 'verb 4' "$_options" 'debug logging disabled'

# The same slot switched to TCP removes UDP-only options while retaining MTU.
sed -i 's/^vpn1_protocol=.*$/vpn1_protocol=TCP/' "$SCRIPT_CONF"
SetVPNCustomSettings 1 legacy 2005000
lacks 'explicit-exit-notify 3' "$_options" 'legacy TCP'
lacks 'mssfix 1450' "$_options" 'legacy TCP'
has 'tun-mtu 1500' "$_options" 'legacy TCP'

# Switch back to UDP, then check 2.6 profile defaults and supported persist-key.
sed -i 's/^vpn1_protocol=.*$/vpn1_protocol=UDP/' "$SCRIPT_CONF"
SetVPNCustomSettings 1 modern 2006000
has 'persist-key' "$_options" '2.6 modern UDP'
lacks 'mssfix 1450' "$_options" '2.6 modern defaults'
lacks 'tun-mtu 1500' "$_options" '2.6 modern defaults'
has 'mute 20' "$_options" 'configured mute'

# 2.7 drops persist-key; zero mute suppresses the directive, debug adds verb 4.
sed -i 's/^vpn1_mute=.*$/vpn1_mute=0/' "$SCRIPT_CONF"
sed -i 's/^vpn1_debugverb=.*$/vpn1_debugverb=true/' "$SCRIPT_CONF"
SetVPNCustomSettings 1 modern 2007000
lacks 'persist-key' "$_options" '2.7 modern UDP'
lacks 'mute 0' "$_options" 'zero mute'
has 'verb 4' "$_options" 'debug logging enabled'
has 'remote-cert-tls server' "$_options" 'trust option retained'
lacks 'fast-io' "$_options" '2.7 modern UDP'

# Per-slot provider/protocol context and default mute are read from SCRIPT_CONF.
SetVPNCustomSettings 4 modern 2007000 'shaper 1000'
_options="$TEST_DIR/openvpn/vpn_client4_custom3"
has 'mute 20' "$_options" 'missing mute default'
has 'verb 4' "$_options" 'slot 4 debug context'
lacks 'mssfix 1450' "$_options" 'other provider UDP'
has 'explicit-exit-notify 3' "$_options" 'other provider UDP'

# Direct menu calls detect the runtime fresh; disabling only flips the flag and
# leaves an existing options block byte-for-byte intact.
TEST_RUNTIME_VERSION=2.6.12
TEST_RUNTIME_NUMBER=2006012
TEST_RUNTIME_FAMILY=modern
TEST_RUNTIME_STATUS=detected
SetVPNCustomSettings 4
cp "$TEST_DIR/openvpn/vpn_client4_custom3" "$TEST_DIR/before-disable"
Toggle_VPN_Custom_Settings 4
state_is 4 true
Toggle_VPN_Custom_Settings 4
state_is 4 false
cmp -s "$TEST_DIR/before-disable" "$TEST_DIR/openvpn/vpn_client4_custom3" || die 'disable changed options block'

# The existing parser deduplicates batch selection; unmanaged and unselected
# slots stay untouched while selected managed slots toggle once.
ParseSlotSelection '1,2-3,2' || die 'batch input rejected'
[ "$GLOBAL_VPN_SLOTS" = '1 2 3' ] || die "unexpected parsed slots: $GLOBAL_VPN_SLOTS"
printf 'prior custom options\n' > "$TEST_DIR/openvpn/vpn_client3_custom3"
cp "$TEST_DIR/openvpn/vpn_client3_custom3" "$TEST_DIR/slot3-before"
for _batch_slot in $GLOBAL_VPN_SLOTS; do
	_batch_managed="$(grep "^vpn${_batch_slot}_managed=" "$SCRIPT_CONF" | cut -d= -f2)"
	if [ "$_batch_managed" = "true" ]; then
		Toggle_VPN_Custom_Settings "$_batch_slot" || die "batch toggle failed for slot $_batch_slot"
	fi
done
state_is 1 true
state_is 2 false
state_is 3 false
state_is 4 false
cmp -s "$TEST_DIR/slot3-before" "$TEST_DIR/openvpn/vpn_client3_custom3" || die 'batch disable changed existing block'

# A preset write failure is reported and leaves the selected slot disabled.
mv "$TEST_DIR/openvpn/vpn_client4_custom3" "$TEST_DIR/slot4-before-write-failure"
mkdir "$TEST_DIR/openvpn/vpn_client4_custom3"
if Toggle_VPN_Custom_Settings 4 2> "$TEST_DIR/write-error"; then die 'failed preset write accepted'; fi
state_is 4 false
grep -q 'remain disabled' "$TEST_DIR/messages" || die 'preset write failure was not reported'
printf 'OpenVPN preset compatibility and toggle checks passed.\n'
