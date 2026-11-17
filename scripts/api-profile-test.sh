#!/bin/sh
# Offline checks of the API consumer's real parsing/probe-config functions.
# The timeout boundary is inert: this never executes OpenVPN or contacts a VPN.
# shellcheck disable=SC2034
set -eu
REPO_ROOT="$(CDPATH='' cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
mkdir -p "$TEST_DIR/openvpn" "$TEST_DIR/work"
for test_fn in getIP getPort getCipher getAuthDigest getClientCA Default_VPN_Data_Ciphers; do
	sed -n "/^${test_fn}(){/,/^}/p" "$REPO_ROOT/vpnmgr.sh"
done > "$TEST_DIR/core.sh"
. "$TEST_DIR/core.sh"
for test_fn in _ac_parse_ovpn _ac_handshake; do
	sed -n "/^${test_fn}(){/,/^}/p" "$REPO_ROOT/scripts/api-check.sh"
done | sed "s|/jffs/openvpn/|$TEST_DIR/openvpn/|g" > "$TEST_DIR/consumer.sh"
. "$TEST_DIR/consumer.sh"
. "$REPO_ROOT/providers/provider_nordvpn.sh"
die(){ printf 'FAIL: %s\n' "$*" >&2; exit 1; }
timeout(){ printf 'AUTH_FAILED\n'; }
openvpn(){ die 'offline fixture attempted to execute OpenVPN'; }
provider_pia_get_hmac(){ printf '1'; }
AC_PROVIDER=nordvpn
AC_WORK="$TEST_DIR/work"
printf 'fixture static key\n' > "$TEST_DIR/openvpn/vpn_crt_client1_static"
for test_protocol in UDP TCP; do
	AC_PROFILE_FAMILY=legacy
	AC_OVPN="$(printf 'remote example.invalid 1194\ncipher AES-256-CBC\nauth SHA512\n<ca>\nfixture CA\n</ca>\nkey-direction 1\n<tls-auth>\nfixture key\n</tls-auth>\n')"
	if ! _ac_parse_ovpn; then die 'legacy profile rejected'; fi
	[ "$AC_NCP_CIPHERS" = 'AES-256-GCM:AES-128-GCM:AES-256-CBC:AES-128-CBC' ] || die 'legacy cipher fallback changed'
	_ac_handshake "$test_protocol"
	grep -qx 'auth SHA512' "$AC_WORK/probe_${test_protocol}.conf" || die 'legacy digest missing'
	grep -Fqx "tls-auth $TEST_DIR/openvpn/vpn_crt_client1_static 1" "$AC_WORK/probe_${test_protocol}.conf" || die 'legacy key/direction missing'
	AC_PROFILE_FAMILY=modern
	AC_OVPN="$(printf 'remote example.invalid 53\n<ca>\nfixture CA\n</ca>\n<tls-crypt>\nfixture key\n</tls-crypt>\n')"
	if ! _ac_parse_ovpn; then die 'modern profile defaults rejected'; fi
	[ "$AC_OVPN_CIPHER" = default ] && [ "$AC_OVPN_DIGEST" = default ] && [ -z "$AC_NCP_CIPHERS" ] || die 'modern defaults changed'
	_ac_handshake "$test_protocol"
	grep -Fqx "tls-crypt $TEST_DIR/openvpn/vpn_crt_client1_static" "$AC_WORK/probe_${test_protocol}.conf" || die 'modern TLS mode missing'
	if grep -Eq '^(auth |data-ciphers |data-ciphers-fallback |key-direction )' "$AC_WORK/probe_${test_protocol}.conf"; then die 'modern defaults replaced by legacy directives'; fi
	grep -qx 'remote-cert-tls server' "$AC_WORK/probe_${test_protocol}.conf" || die 'server verification missing'
	AC_OVPN="$AC_OVPN
data-ciphers AES-256-GCM:AES-128-GCM"
	if ! _ac_parse_ovpn; then die 'explicit modern data ciphers rejected'; fi
	_ac_handshake "$test_protocol"
	grep -qx 'data-ciphers AES-256-GCM:AES-128-GCM' "$AC_WORK/probe_${test_protocol}.conf" || die 'explicit data ciphers ignored'
done
AC_PROFILE_FAMILY=legacy
if _ac_parse_ovpn; then die 'legacy consumer accepted missing cipher/auth'; fi
AC_PROVIDER=pia
AC_PROFILE_FAMILY=modern
if _ac_parse_ovpn; then die 'other provider validation weakened'; fi
printf 'API profile consumer/config checks passed (offline; no handshake executed).\n'
