#!/bin/sh
# Offline real-function checks; also runs directly under BusyBox ash in CI.
set -eu
REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
for test_fn in Parse_OpenVPN_Version Detect_OpenVPN_Runtime OpenVPN_Version_Number; do
	sed -n "/^${test_fn}(){/,/^}/p" "$REPO_ROOT/vpnmgr.sh"
done | sed "s|/usr/sbin/openvpn|$TEST_DIR/openvpn|g" > "$TEST_DIR/functions.sh"
. "$TEST_DIR/functions.sh"
sed -n '/^provider_nordvpn_get_ovpn(){/,/^}/p' "$REPO_ROOT/providers/provider_nordvpn.sh" \
	| sed 's|/usr/sbin/curl|fixture_curl|g' > "$TEST_DIR/provider.sh"
. "$TEST_DIR/provider.sh"
cat > "$TEST_DIR/openvpn" <<'EOF'
#!/bin/sh
printf '%s\n' "$OVPN_TEST_BANNER"
exit "${OVPN_TEST_EXIT:-0}"
EOF
chmod +x "$TEST_DIR/openvpn"
export OVPN_TEST_BANNER OVPN_TEST_EXIT
OVPN_TEST_EXIT=0
# Used by the extracted production detector.
# shellcheck disable=SC2034
WARN=""
TEST_COUNT=0
Print_Output(){ printf '%s\n' "$2" >> "$TEST_DIR/diagnostics"; }
openvpn(){ printf 'FAIL: PATH OpenVPN must never be executed\n' >&2; exit 1; }
fixture_curl(){
	for test_arg do
		case "$test_arg" in https://*) printf '%s' "$test_arg" ;; esac
	done
}
assert_eq(){
	TEST_COUNT=$((TEST_COUNT + 1))
	if [ "$2" != "$3" ]; then
		printf 'FAIL: %s: expected <%s>, got <%s>\n' "$1" "$2" "$3" >&2
		exit 1
	fi
}
check_version(){
	OVPN_TEST_BANNER="$1"
	Detect_OpenVPN_Runtime
	assert_eq "$1" "$2" "$OVPN_RUNTIME_STATUS|$OVPN_RUNTIME_VERSION|$OVPN_RUNTIME_NUMBER|$OVPN_RUNTIME_FAMILY"
}
check_version 'OpenVPN 2.4.9 arm-linux [SSL]' 'detected|2.4.9|2004009|legacy'
check_version 'OpenVPN 2.5.99 arm-linux' 'detected|2.5.99|2005099|legacy'
check_version 'OpenVPN 2.6 arm-linux' 'detected|2.6|2006000|modern'
check_version 'OpenVPN 2.6.12-vendor arm-linux' 'detected|2.6.12-vendor|2006012|modern'
check_version 'OpenVPN 2.7_rc1 arm-linux' 'detected|2.7_rc1|2007000|modern'
check_version 'OpenVPN 2.10.3+vendor arm-linux' 'detected|2.10.3+vendor|2010003|modern'
check_version 'OpenVPN 3.0.0 arm-linux' 'detected|3.0.0|3000000|modern'
for test_banner in '' 'OpenSSL 3.5.9' 'OpenVPN banana' 'OpenVPN 2.x.0' \
	'OpenVPN 2.6garbage' 'OpenVPN 2.6.1.2' 'OpenVPN 1.6.0' 'OpenVPN 2.1000.0'; do
	check_version "$test_banner" 'unknown|||legacy'
done
OVPN_TEST_EXIT=7
check_version 'OpenVPN 2.6.12 arm-linux' 'unknown|||legacy'
OVPN_TEST_EXIT=0
chmod -x "$TEST_DIR/openvpn"
check_version 'OpenVPN 2.6.12 arm-linux' 'unknown|||legacy'
chmod +x "$TEST_DIR/openvpn"
[ -s "$TEST_DIR/diagnostics" ] || { printf 'FAIL: unknown version has no diagnostic\n' >&2; exit 1; }
check_version 'OpenVPN 2.6.12 arm-linux' 'detected|2.6.12|2006012|modern'
for test_protocol in UDP TCP; do
	test_lower="$(printf '%s' "$test_protocol" | tr 'A-Z' 'a-z')"
	test_base="https://downloads.nordcdn.com/configs/files/ovpn_${test_lower}/servers/au1046.nordvpn.com.${test_lower}"
	assert_eq "default $test_protocol" "$test_base.ovpn" "$(provider_nordvpn_get_ovpn au1046.nordvpn.com "$test_protocol" Standard)"
	assert_eq "legacy $test_protocol" "$test_base.ovpn" "$(provider_nordvpn_get_ovpn au1046.nordvpn.com "$test_protocol" Standard legacy)"
	assert_eq "modern $test_protocol" "${test_base}_2.6.ovpn" "$(provider_nordvpn_get_ovpn au1046.nordvpn.com "$test_protocol" Standard "$OVPN_RUNTIME_FAMILY")"
done
if provider_nordvpn_get_ovpn au1046.nordvpn.com UDP Standard invalid; then
	printf 'FAIL: unsupported profile family accepted\n' >&2
	exit 1
fi
assert_eq 'provider leaves canonical operation context intact' modern "$OVPN_RUNTIME_FAMILY"
printf '%s OpenVPN runtime/profile checks passed (%s).\n' "$TEST_COUNT" "${VPNMGR_TEST_RUNTIME:-local sh}"
