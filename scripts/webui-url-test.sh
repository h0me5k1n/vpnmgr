#!/usr/bin/env bash
# Exercise the real Get_WebUI_URL function against isolated menu-tree fixtures.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_FILE="${1:-${REPO_ROOT}/vpnmgr.sh}"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

EXTRACT="${TEST_DIR}/Get_WebUI_URL.sh"
sed -n '/^Get_WebUI_URL(){/,/^}/p' "$SOURCE_FILE" \
    | sed 's|/tmp/menuTree.js|"${_WUI_CACHED}"|g; s|/www/require/modules/menuTree.js|"${_WUI_ACTIVE}"|g' \
    > "$EXTRACT"

if [[ ! -s "$EXTRACT" ]]; then
    echo "Get_WebUI_URL() not found in source: ${SOURCE_FILE}" >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$EXTRACT"

_WUI_ACTIVE="${TEST_DIR}/active-menuTree.js"
_WUI_CACHED="${TEST_DIR}/cached-menuTree.js"
export SCRIPT_NAME="vpnmgr"
PASS=0
FAIL=0
HTTP_ENABLE=1
LAN_DOMAIN="lan"
LAN_HOSTNAME="router"
LAN_IPADDR="192.168.50.1"
HTTPS_PORT=8443
HTTP_PORT=80

nvram() {
    [[ "$1" == get ]] || return 1
    case "$2" in
        http_enable) printf '%s\n' "$HTTP_ENABLE" ;;
        lan_domain) printf '%s\n' "$LAN_DOMAIN" ;;
        lan_hostname) printf '%s\n' "$LAN_HOSTNAME" ;;
        lan_ipaddr) printf '%s\n' "$LAN_IPADDR" ;;
        https_lanport) printf '%s\n' "$HTTPS_PORT" ;;
        http_lanport) printf '%s\n' "$HTTP_PORT" ;;
        *) return 1 ;;
    esac
}

assert_url() {
    local description="$1" expected="$2" actual
    actual="$(Get_WebUI_URL)"
    if [[ "$actual" == "$expected" ]]; then
        printf 'PASS %s\n' "$description"
        PASS=$((PASS + 1))
    else
        printf 'FAIL %s (expected %s, got %s)\n' "$description" "$expected" "$actual" >&2
        FAIL=$((FAIL + 1))
    fi
}

# The active tree is authoritative even when the cached copy has no entry.
printf '{url: "user7.asp", tabName: "vpnmgr"},\n' > "$_WUI_ACTIVE"
: > "$_WUI_CACHED"
assert_url "active slot 7 formats the HTTPS URL" "https://router.lan:8443/user7.asp"

# Resolve the active slot dynamically when the local installation uses user8.
printf '{url: "user8.asp", tabName: "vpnmgr"},\n' > "$_WUI_ACTIVE"
printf '{url: "user7.asp", tabName: "vpnmgr"},\n' > "$_WUI_CACHED"
HTTP_ENABLE=0
assert_url "active slot 8 wins over a stale cached slot 7" "http://router.lan/user8.asp"

# A stale cached URL must not be reported if the active tree no longer has it.
: > "$_WUI_ACTIVE"
assert_url "missing active entry does not report stale cached URL" "WebUI page not found"

printf '%s of %s WebUI URL tests passed.\n' "$((PASS))" "$((PASS + FAIL))"
[[ "$FAIL" -eq 0 ]]
