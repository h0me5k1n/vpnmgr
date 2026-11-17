#!/usr/bin/env bash
# Offline consumer regression tests; never source vpnmgr.sh's command dispatcher.
set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW_TEST_SOURCE="${1:-$REPO_ROOT/vpnmgr.sh}"
_FW_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$_FW_TEST_DIR"' EXIT
mkdir -p "$_FW_TEST_DIR/openvpn"

for fn in Firmware_Number_Check Firmware_Build_Before Validate_Number \
    getIP getPort getCipher getAuthDigest getClientCA getConnectState \
    UpdateVPNConfig SetVPNCustomSettings Write_VPNCustomOptions Strip_Stale_X509Name; do
    sed -n "/^${fn}(){/,/^}/p" "$FW_TEST_SOURCE"
done | sed -e 's@/jffs/openvpn/@"$_FW_TEST_DIR"/openvpn/@g' \
    -e 's@/bin/uname@uname@g' > "$_FW_TEST_DIR/functions.sh"
if grep -q '/jffs/' "$_FW_TEST_DIR/functions.sh"; then
    echo 'FAIL: extracted functions contain an unisolated router path' >&2
    exit 1
fi
# shellcheck source=/dev/null
. "$_FW_TEST_DIR/functions.sh"

die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || die "$3: expected '$1', got '$2'"; }

nvram() {
    case "$1" in
        get)
            case "$2" in
                firmver) printf '%s\n' "$FW_TEST_FAMILY" ;;
                buildno) printf '%s\n' "$FW_TEST_BUILD" ;;
                vpn_client1_addr|vpn_client1_port|vpn_client1_proto) : ;;
                vpn_clientx_eas) printf '1\n' ;;
                vpn_client1_state) printf '2\n' ;;
                vpn_client1_rgw) printf '0\n' ;;
                vpn_client1_username|vpn_client1_password) printf 'fixture\n' ;;
                vpn_client1_cust2) printf '%s\n' "$FW_TEST_CUST2" ;;
                *) die "unexpected NVRAM read: $2" ;;
            esac
            ;;
        set) printf '%s\n' "$2" >> "$FW_TEST_NVRAM_LOG" ;;
        commit) : ;;
        *) die "unexpected NVRAM operation: $1" ;;
    esac
}

# Router/provider boundaries are inert; the real update, parsing, compatibility
# decisions and custom-options generator execute against the fixture below.
Print_Output() { :; }
Load_Provider() { [[ "$1" == nordvpn ]]; }
OpenVPN_Version_Number() { printf '2007000\n'; }
provider_nordvpn_get_server() { printf 'au1123.nordvpn.com\n'; }
provider_nordvpn_get_ovpn() { printf '%s\n' "$FW_TEST_PROFILE"; }
provider_nordvpn_get_short_name() { printf 'AU1123\n'; }
provider_nordvpn_get_desc() { printf 'Fixture AU1123\n'; }
provider_nordvpn_get_comp() { printf 'no\n'; }
provider_nordvpn_get_hmac() { printf '1\n'; }
provider_nordvpn_write_certs() { printf '%s\n' "$CLIENT_CA" > "$FW_TEST_CA_LOG"; }
RestartVPNClient() { printf '%s\n' "$1" >> "$FW_TEST_RESTART_LOG"; }
service() { die 'unexpected service operation'; }
curl() { die 'unexpected network operation'; }
ping() { die 'unexpected network operation'; }
sleep() { die 'unexpected connection wait'; }
uname() {
    case "$1" in
        -m) printf 'x86_64\n' ;;
        -o) printf 'ASUSWRT-Merlin\n' ;;
        *) die 'unexpected uname operation' ;;
    esac
}
head() {
    if [[ "$1" == -c && "$2" == -1 ]]; then
        # The router uses BusyBox/GNU head to remove echo's final newline.
        # Bash command substitution does the same for these option strings on macOS.
        local options
        options="$(cat)"
        printf '%s' "$options"
    else
        command head "$@"
    fi
}

run_case() (
    local label="$1" route="$4" retry_value="$5" storage="$6" managed="$7" pin="${8:-pin}"
    # These globals are inputs/outputs of the extracted production functions.
    # shellcheck disable=SC2034
    FW_TEST_FAMILY="$2" FW_TEST_BUILD="$3" SCRIPT_CONF="$_FW_TEST_DIR/config" \
        FW_TEST_NVRAM_LOG="$_FW_TEST_DIR/nvram.log" FW_TEST_CA_LOG="$_FW_TEST_DIR/ca.log" \
        FW_TEST_RESTART_LOG="$_FW_TEST_DIR/restart.log"
    : > "$FW_TEST_NVRAM_LOG"
    : > "$FW_TEST_RESTART_LOG"
    cat > "$SCRIPT_CONF" <<EOF
vpn1_provider=NordVPN
vpn1_protocol=UDP
vpn1_type=Standard
vpn1_countryid=13
vpn1_countryname=Australia
vpn1_cityid=0
vpn1_cityname=
vpn1_customsettings=$managed
vpn1_mute=20
vpn1_debugverb=false
EOF
    FW_TEST_PROFILE='remote 192.0.2.123 1231
cipher AES-256-CBC
auth SHA512
verify-x509-name CN=au1123.nordvpn.com
<ca>
fixture-ca
</ca>'
    if [[ "$pin" == pin ]]; then
        printf 'verify-x509-name CN=au1164.nordvpn.com\nremote-cert-tls server\n' \
            > "$_FW_TEST_DIR/openvpn/vpn_client1_custom3"
    else
        printf 'remote-cert-tls server\n' > "$_FW_TEST_DIR/openvpn/vpn_client1_custom3"
    fi
    cp "$_FW_TEST_DIR/openvpn/vpn_client1_custom3" "$_FW_TEST_DIR/imported-options"
    # Legacy firmware keeps the same block base64-encoded in NVRAM.
    # shellcheck disable=SC2034
    FW_TEST_CUST2="$(printf '%s' "$(cat "$_FW_TEST_DIR/imported-options")" | openssl base64 -A)"

    UpdateVPNConfig unattended 1 2

    grep -qx "vpn_client1_connretry=$retry_value" "$FW_TEST_NVRAM_LOG" || die "$label retry value"
    case "$route" in
        first) grep -qx 'vpn_client1_clientlist=<DummyVPN>172.16.14.1>0.0.0.0>VPN' "$FW_TEST_NVRAM_LOG" || die "$label routing format" ;;
        second) grep -qx 'vpn_client1_clientlist=<DummyVPN>172.16.14.1>>VPN' "$FW_TEST_NVRAM_LOG" || die "$label routing format" ;;
        none) ! grep -q '^vpn_client1_clientlist=' "$FW_TEST_NVRAM_LOG" || die "$label added legacy routing" ;;
    esac
    assert_eq 'fixture-ca' "$(cat "$FW_TEST_CA_LOG")" "$label selected profile CA"
    assert_eq '1' "$(cat "$FW_TEST_RESTART_LOG")" "$label fake restart boundary"
    if [[ "$managed" == false && "$storage" == file ]]; then
        # Only the stale certificate-name pin goes; everything else stays byte-for-byte.
        grep -v '^verify-x509-name ' "$_FW_TEST_DIR/imported-options" > "$_FW_TEST_DIR/expected-options" || true
        cmp -s "$_FW_TEST_DIR/expected-options" "$_FW_TEST_DIR/openvpn/vpn_client1_custom3" || die "$label changed user-managed options beyond the pin"
        ! grep -Eq '^vpn_client1_(cust2|cust21|cust22|custom)=' "$FW_TEST_NVRAM_LOG" || die "$label wrote legacy options"
    elif [[ "$managed" == false ]]; then
        cmp -s "$_FW_TEST_DIR/imported-options" "$_FW_TEST_DIR/openvpn/vpn_client1_custom3" || die "$label changed unused modern storage"
        if [[ "$pin" == pin ]]; then
            grep -qx "vpn_client1_cust2=$(printf 'remote-cert-tls server' | openssl base64 -A)" "$FW_TEST_NVRAM_LOG" || die "$label kept the legacy pin"
        else
            ! grep -Eq '^vpn_client1_(cust2|cust21|cust22|custom)=' "$FW_TEST_NVRAM_LOG" || die "$label rewrote legacy options without a pin"
        fi
    elif [[ "$storage" == file ]]; then
        grep -qx 'remote-cert-tls server' "$_FW_TEST_DIR/openvpn/vpn_client1_custom3" || die "$label lost server-role verification"
        grep -qx 'auth-nocache' "$_FW_TEST_DIR/openvpn/vpn_client1_custom3" || die "$label omitted managed options"
        ! grep -q '^verify-x509-name ' "$_FW_TEST_DIR/openvpn/vpn_client1_custom3" || die "$label retained an imported pin"
        ! grep -Eq '^vpn_client1_(cust2|cust21|cust22|custom)=' "$FW_TEST_NVRAM_LOG" || die "$label wrote legacy options"
    else
        grep -Eq '^vpn_client1_(cust2|custom)=' "$FW_TEST_NVRAM_LOG" || die "$label omitted legacy options"
        cmp -s "$_FW_TEST_DIR/imported-options" "$_FW_TEST_DIR/openvpn/vpn_client1_custom3" || die "$label changed unused modern storage"
    fi
    printf '  PASS: %s\n' "$label"
)

run_case '384.17 legacy boundaries' 3.0.0.4 384.17 first -1 legacy true
run_case '384.18 routing transition' 3.0.0.4 384.18 second -1 legacy true
run_case '384.19 retry transition' 3.0.0.4 384.19 second 0 legacy true
run_case '386.3 custom-storage transition' 3.0.0.4 386.3 none 0 file true
run_case '388.12 existing firmware behavior' 3.0.0.4 388.12 none 0 file true
run_case '3006.102.9 managed imported profile' 3.0.0.6 102.9 none 0 file true
run_case 'missing family retains legacy comparison' '' 384.18 second -1 legacy true
run_case 'unknown family retains build comparison' unknown 388.12 none 0 file true
run_case '388.12 user-managed stale pin removed' 3.0.0.4 388.12 none 0 file false
run_case '3006.102.9 user-managed stale pin removed' 3.0.0.6 102.9 none 0 file false
run_case '3006.102.9 user-managed options without a pin untouched' 3.0.0.6 102.9 none 0 file false nopin
run_case '384.19 user-managed legacy stale pin removed' 3.0.0.4 384.19 second 0 legacy false
run_case '384.19 user-managed legacy options without a pin untouched' 3.0.0.4 384.19 second 0 legacy false nopin
printf 'All 13 firmware consumer cases passed.\n'
