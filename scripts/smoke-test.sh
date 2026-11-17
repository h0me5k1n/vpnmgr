#!/usr/bin/env bash
# smoke-test.sh
#
# Validates vpnmgr.sh and provider modules: syntax, shellcheck, provider contract
# completeness, repo hygiene, and attribution.
#
# Usage:
#   ./scripts/smoke-test.sh
#   ./scripts/smoke-test.sh --offline   (alias — all tests are offline)
#
# Exit code: 0 = all tests passed, 1 = one or more failures.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

pass()    { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail()    { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
warn()    { echo -e "  ${YELLOW}!${NC} $1"; }
section() { echo -e "\n${BOLD}${BLUE}$1${NC}"; }

PASS=0
FAIL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

echo -e "\n${BOLD}Smoke Test — vpnmgr${NC}"
echo "Repo: ${REPO_ROOT}"

# ---------------------------------------------------------------------------
# Section 1: Syntax + shellcheck on all shell scripts
#
# These are ash (POSIX sh) scripts. sh -n checks syntax; shellcheck
# is run with --shell=sh to match the actual target environment.
# ---------------------------------------------------------------------------
section "1. Syntax and static analysis"

SHELL_SCRIPTS=(vpnmgr.sh)

while IFS= read -r -d '' f; do
    SHELL_SCRIPTS+=("${f#${REPO_ROOT}/}")
done < <(find "${REPO_ROOT}/providers" -name '*.sh' -print0 2>/dev/null | sort -z)

# The API check runs under busybox ash in CI, so it is held to the same rules.
SHELL_SCRIPTS+=(scripts/api-check.sh scripts/api-check-report.sh scripts/changelog-notes.sh)
while IFS= read -r -d '' f; do
    SHELL_SCRIPTS+=("${f#${REPO_ROOT}/}")
done < <(find "${REPO_ROOT}/scripts/api-checks" -name '*.sh' -print0 2>/dev/null | sort -z)

SHELLCHECK_AVAILABLE=false
if command -v shellcheck &>/dev/null; then
    SHELLCHECK_AVAILABLE=true
fi

for script in "${SHELL_SCRIPTS[@]}"; do
    if [[ ! -f "$script" ]]; then
        fail "${script} — file not found"
        continue
    fi

    if sh -n "$script" 2>/dev/null; then
        pass "${script} — sh -n"
    else
        fail "${script} — sh -n: $(sh -n "$script" 2>&1)"
        continue
    fi

    if [[ "$SHELLCHECK_AVAILABLE" == true ]]; then
        sc_out=$(shellcheck --shell=sh --severity=warning "$script" 2>&1) || true
        if [[ -z "$sc_out" ]]; then
            pass "${script} — shellcheck"
        else
            fail "${script} — shellcheck"
            echo "$sc_out" | sed 's/^/    /'
        fi
    fi
done

if [[ "$SHELLCHECK_AVAILABLE" == false ]]; then
    warn "shellcheck not found — skipping static analysis (install: apt install shellcheck)"
fi

# ---------------------------------------------------------------------------
# Section 2: Provider contract completeness
#
# The core dispatches to these 18 functions for every configured provider.
# Verify each non-template provider module implements all of them.
# ---------------------------------------------------------------------------
section "2. Provider contract"

REQUIRED_FUNCS=(
    version
    get_server
    get_ovpn
    get_comp
    get_hmac
    get_short_name
    get_desc
    write_certs
    get_country_names
    get_country_id
    get_city_count
    get_city_names
    get_city_id
    country_required
    city_required
    get_types
    get_server_load
    refresh_cache
)

if [[ ! -d "${REPO_ROOT}/providers" ]]; then
    warn "providers/ directory not found — skipping contract checks"
else
    provider_count=0
    while IFS= read -r -d '' pfile; do
        pname=$(basename "$pfile" .sh | sed 's/^provider_//')
        [[ "$pname" == "template" ]] && continue
        provider_count=$((provider_count + 1))
        for fn in "${REQUIRED_FUNCS[@]}"; do
            fqfn="provider_${pname}_${fn}"
            if grep -q "^${fqfn}(){" "$pfile" || grep -q "^${fqfn}() {" "$pfile"; then
                pass "${pname}: ${fn}()"
            else
                fail "${pname}: missing ${fqfn}()"
            fi
        done
    done < <(find "${REPO_ROOT}/providers" -name 'provider_*.sh' -print0 | sort -z)

    if [[ $provider_count -eq 0 ]]; then
        warn "No non-template provider modules found in providers/"
    fi
fi

# ---------------------------------------------------------------------------
# Section 3: Repo hygiene — no provider config files committed
# ---------------------------------------------------------------------------
section "3. Repo hygiene"

for pat in '*.ovpn' '*.zip' '*.p12' '*.pem'; do
    hits=$(git -C "${REPO_ROOT}" ls-files "$pat" 2>/dev/null || true)
    if [[ -z "$hits" ]]; then
        pass "No ${pat} files committed"
    else
        fail "Committed ${pat} files found (must download at runtime, never commit):"
        echo "$hits" | sed 's/^/    /'
    fi
done

# ---------------------------------------------------------------------------
# Section 4: Core cleanliness — no inline provider API URLs in vpnmgr.sh
#
# Provider-specific API endpoints belong in provider modules, not the core.
# ---------------------------------------------------------------------------
section "4. Core script cleanliness"

for pat in 'api\.nordvpn\.com' 'nordcdn\.com' 'privateinternetaccess\.com' 'wevpn\.com'; do
    hits=$(grep -n "$pat" "${REPO_ROOT}/vpnmgr.sh" 2>/dev/null || true)
    if [[ -z "$hits" ]]; then
        pass "vpnmgr.sh: no inline ${pat}"
    else
        fail "vpnmgr.sh: provider-specific URL found (should be in provider module):"
        echo "$hits" | sed 's/^/    /'
    fi
done

# ---------------------------------------------------------------------------
# Section 5: Attribution — SCRIPT_REPO points to h0me5k1n
# ---------------------------------------------------------------------------
section "5. Attribution"

if grep -q 'SCRIPT_REPO=.*h0me5k1n' "${REPO_ROOT}/vpnmgr.sh"; then
    repo_val=$(grep 'SCRIPT_REPO=' "${REPO_ROOT}/vpnmgr.sh" | head -1 | sed 's/.*="\(.*\)"/\1/')
    pass "SCRIPT_REPO → ${repo_val}"
else
    actual=$(grep 'SCRIPT_REPO=' "${REPO_ROOT}/vpnmgr.sh" | head -1 || echo "(not found)")
    fail "SCRIPT_REPO does not point to h0me5k1n — got: ${actual}"
fi

# ---------------------------------------------------------------------------
# Section 6: Provider status headers
#
# The status must be one of the known values. API_TESTED and ACTIVE both claim
# that the provider's API has been checked, so each needs a check spec in
# scripts/api-checks/ for the scheduled API check to keep that claim true.
# ---------------------------------------------------------------------------
section "6. Provider status headers"

if [[ -d "${REPO_ROOT}/providers" ]]; then
    while IFS= read -r -d '' pfile; do
        pname=$(basename "$pfile" .sh | sed 's/^provider_//')
        if grep -q '^# Status:' "$pfile"; then
            status=$(grep '^# Status:' "$pfile" | head -1 | sed 's/^# Status: *//')
            status_word=$(awk '{print $1}' <<< "$status")
            case "$status_word" in
                ACTIVE|API_TESTED|UNTESTED|UNMAINTAINED|DEPRECATED|TEMPLATE)
                    pass "${pname}: Status: ${status}"
                    ;;
                *)
                    fail "${pname}: unknown status '${status_word}' (expected ACTIVE, API_TESTED, UNTESTED, UNMAINTAINED, DEPRECATED or TEMPLATE)"
                    ;;
            esac
            case "$status_word" in
                ACTIVE|API_TESTED)
                    if [[ -f "${REPO_ROOT}/scripts/api-checks/${pname}.sh" ]] \
                        && grep -q "^api_check_${pname}(){" "${REPO_ROOT}/scripts/api-checks/${pname}.sh"; then
                        pass "${pname}: has API check spec (required for ${status_word})"
                    else
                        fail "${pname}: status ${status_word} requires scripts/api-checks/${pname}.sh defining api_check_${pname}()"
                    fi
                    ;;
            esac
        else
            fail "${pname}: missing '# Status:' header"
        fi
    done < <(find "${REPO_ROOT}/providers" -name 'provider_*.sh' -print0 | sort -z)
fi

# ---------------------------------------------------------------------------
# Section 7: .gitignore coverage
# ---------------------------------------------------------------------------
section "7. .gitignore coverage"

for pat in '*.ovpn' '*.zip' '*.p12' '*.pem'; do
    if grep -qF "$pat" "${REPO_ROOT}/.gitignore" 2>/dev/null; then
        pass ".gitignore: ${pat}"
    else
        fail ".gitignore missing ${pat} — provider config files could be accidentally committed"
    fi
done

# ---------------------------------------------------------------------------
# Section 8: WebUI files
# ---------------------------------------------------------------------------
section "8. WebUI files"

WEBUI_JS="${REPO_ROOT}/vpnmgr_www.js"

# No ES6+ in the JS file — router WebKit does not support ES6
for pat in '\blet ' '\bconst ' '=>' '`' '\bfetch('; do
    hits=$(grep -n "$pat" "$WEBUI_JS" || true)
    if [[ -z "$hits" ]]; then
        pass "vpnmgr_www.js: no ES6+ pattern (${pat})"
    else
        fail "vpnmgr_www.js: ES6+ pattern '${pat}' found (not safe on router WebKit):"
        echo "$hits" | sed 's/^/    /'
    fi
done

# TODO (Phase 5): JS syntax check via node
# TODO (Phase 5): jQuery uses \$j not \$ (noConflict — \$ clashes with Merlin's prototype.js)
# TODO (Phase 5): No hardcoded country arrays — must load dynamically from provider data files
# TODO (Phase 5): CSS syntax check via stylelint

# ---------------------------------------------------------------------------
# Section 9: NordVPN label/parsing (offline, no network)
#
# provider_nordvpn_get_desc() and provider_nordvpn_get_server_load() are pure
# string/cache-file logic — no live API calls needed to exercise them. This
# guards the full/compact label format and the round-trip back through
# get_server_load() (which must recover the server id from whatever get_desc()
# produced, in legacy, full, or compact form) without needing a router.
# ---------------------------------------------------------------------------
section "9. NordVPN label/parsing (offline)"

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$desc"
    else
        fail "$desc (expected '${expected}', got '${actual}')"
    fi
}

_ORIG_SCRIPT_DIR="$SCRIPT_DIR"
SCRIPT_DIR="$(mktemp -d)"
_NORD_PATCHED="$SCRIPT_DIR/provider_nordvpn.sh"
sed 's|/usr/sbin/curl|curl --globoff|g' "${REPO_ROOT}/providers/provider_nordvpn.sh" > "$_NORD_PATCHED"
# shellcheck source=/dev/null
. "$_NORD_PATCHED"

# Full format is used as-is when short enough to fit the 25-char limit
printf 'A|A|A\n' > "$SCRIPT_DIR/nordvpn_meta_a"
assert_eq "get_desc: full format used when it fits within 25 chars" \
    "A (A) - A [UDP] [P2P] - a" \
    "$(provider_nordvpn_get_desc a.nordvpn.com A UDP P2P)"

# Missing city -> "Country Wide" in full format
printf 'Example Country|XX|\n' > "$SCRIPT_DIR/nordvpn_meta_xx333"
_desc_missing_city="$(provider_nordvpn_get_desc xx333.nordvpn.com XX333 UDP Standard)"
case "$_desc_missing_city" in
    *"Wide"*) pass "get_desc: missing city -> Wide (full or compact)" ;;
    *)        fail "get_desc: missing city did not produce 'Wide' (got '${_desc_missing_city}')" ;;
esac

# Missing country -> "Unknown" (only reachable in full format; realistic
# long/blank combos push this case into compact, where country name is
# dropped entirely by design — checked separately below)
printf '|XX|Example City\n' > "$SCRIPT_DIR/nordvpn_meta_xx777"
_desc_missing_country="$(provider_nordvpn_get_desc xx777.nordvpn.com XX777 UDP Standard)"
case "$_desc_missing_country" in
    *"Unknown"*|"XX "*) pass "get_desc: missing country -> Unknown (full) or dropped (compact)" ;;
    *) fail "get_desc: missing country handled unexpectedly (got '${_desc_missing_country}')" ;;
esac

# Structural invariants on realistic (long) metadata that forces compact fallback
printf 'A Very Long Country Name Indeed|XX|A Very Long City Name Alpha\n' > "$SCRIPT_DIR/nordvpn_meta_xx123456"
_desc_compact="$(provider_nordvpn_get_desc xx123456.nordvpn.com XX123456 UDP Double)"
_len_compact=${#_desc_compact}
if [[ $_len_compact -le 25 ]]; then
    pass "get_desc: compact fallback stays within 25 chars (len=${_len_compact})"
else
    fail "get_desc: compact fallback exceeded 25 chars (len=${_len_compact}): ${_desc_compact}"
fi
case "$_desc_compact" in
    *xx123456) pass "get_desc: compact fallback preserves the full server id" ;;
    *)         fail "get_desc: compact fallback did not end with the server id (got '${_desc_compact}')" ;;
esac
case "$_desc_compact" in
    *"Dbl"*) pass "get_desc: compact fallback abbreviates Double -> Dbl" ;;
    *)       fail "get_desc: compact fallback missing Dbl abbreviation (got '${_desc_compact}')" ;;
esac
case "$_desc_compact" in
    *"  "*) fail "get_desc: compact fallback contains a double space (got '${_desc_compact}')" ;;
    *)      pass "get_desc: compact fallback has no double-space artifacts" ;;
esac

# Country code unavailable -> no bare "(CC)" token, still resolves cleanly
printf 'Example Country||Example City\n' > "$SCRIPT_DIR/nordvpn_meta_xx444"
_desc_no_cc="$(provider_nordvpn_get_desc xx444.nordvpn.com XX444 TCP P2P)"
case "$_desc_no_cc" in
    *"()"*) fail "get_desc: missing country code left an empty '()' token (got '${_desc_no_cc}')" ;;
    *)      pass "get_desc: missing country code produces no empty '()' token" ;;
esac

# Round-trip: get_server_load() must recover the server id load from every
# desc format get_desc() can produce, plus the pre-existing legacy format.
printf '42\n' > "$SCRIPT_DIR/nordvpn_load_gb1"
assert_eq "get_server_load: round-trips a full-format desc" \
    "42" "$(provider_nordvpn_get_server_load "$(provider_nordvpn_get_desc gb1.nordvpn.com GB1 UDP P2P)")"

printf '17\n' > "$SCRIPT_DIR/nordvpn_load_xx123456"
assert_eq "get_server_load: round-trips a compact-format desc" \
    "17" "$(provider_nordvpn_get_server_load "$_desc_compact")"

printf '55\n' > "$SCRIPT_DIR/nordvpn_load_xx111"
assert_eq "get_server_load: still resolves the pre-existing legacy format" \
    "55" "$(provider_nordvpn_get_server_load "NordVPN XX111 Standard UDP")"

assert_eq "get_server_load: reports Unknown for an uncached server" \
    "Unknown" "$(provider_nordvpn_get_server_load "$(provider_nordvpn_get_desc zz999.nordvpn.com ZZ999 UDP Standard)")"

rm -rf "$SCRIPT_DIR"
SCRIPT_DIR="$_ORIG_SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Section 10: CLI slot-selection parsing (offline, no router)
#
# ParseSlotSelection() lives inside vpnmgr.sh, which can't be sourced
# directly for testing: with no args it launches the interactive MainMenu
# (blocks on stdin), and with any arg it falls into the real command
# dispatcher, which touches nvram and other router-only commands. Instead,
# extract just ParseSlotSelection() and its Validate_Number() dependency
# and source only that.
# ---------------------------------------------------------------------------
section "10. CLI slot-selection parsing (offline)"

_PSS_EXTRACT="$(mktemp)"
sed -n '/^Validate_Number(){/,/^}/p' "${REPO_ROOT}/vpnmgr.sh" > "$_PSS_EXTRACT"
sed -n '/^ParseSlotSelection(){/,/^}/p' "${REPO_ROOT}/vpnmgr.sh" >> "$_PSS_EXTRACT"
# shellcheck source=/dev/null
. "$_PSS_EXTRACT"
rm -f "$_PSS_EXTRACT"

assert_slots() {
    local desc="$1" input="$2" expected="$3"
    GLOBAL_VPN_SLOTS=""
    if ParseSlotSelection "$input"; then
        if [[ "$GLOBAL_VPN_SLOTS" == "$expected" ]]; then
            pass "$desc"
        else
            fail "$desc (expected slots '${expected}', got '${GLOBAL_VPN_SLOTS}')"
        fi
    else
        fail "$desc (expected slots '${expected}', but input was rejected)"
    fi
}

assert_rejected() {
    local desc="$1" input="$2"
    GLOBAL_VPN_SLOTS=""
    if ParseSlotSelection "$input"; then
        fail "$desc (expected rejection, got slots '${GLOBAL_VPN_SLOTS}')"
    else
        pass "$desc"
    fi
}

assert_slots "single slot" "3" "3"
assert_slots "range" "1-5" "1 2 3 4 5"
assert_slots "comma list, preserves entry order" "1,4,2" "1 4 2"
assert_slots "mixed range + comma" "1-3,5" "1 2 3 5"
assert_slots "dedups in first-occurrence order" "1,1,2" "1 2"
assert_rejected "empty input"          ""
assert_rejected "non-numeric input"    "abc"
assert_rejected "below range (0)"      "0"
assert_rejected "above range (6)"      "6"
assert_rejected "reversed range"       "5-2"
assert_rejected "dangling range start" "-3"
assert_rejected "dangling range end"   "3-"
assert_rejected "double comma"         "1,,2"
assert_rejected "leading comma"        ",1,2"
assert_rejected "trailing comma"       "1,2,"
assert_rejected "comma-only token"     "1,-,2"
assert_rejected "double-dash range"    "1--3"
assert_rejected "triple-dash range"    "1-2-3"

# ---------------------------------------------------------------------------
# Section 11: Update delivers WebUI JS and provider modules (offline)
#
# vpnmgr_www.js and providers/ are separate downloads from vpnmgr.sh. Both
# Update_Version paths must refresh them, and Sync_Addon_Files must catch up
# on first run after an update performed by an older version's updater.
# Same extraction approach as section 10, with the downloads stubbed.
# ---------------------------------------------------------------------------
section "11. Update refreshes WebUI JS and providers (offline)"

_uv_calls="$(sed -n '/^Update_Version(){/,/^}/p' "${REPO_ROOT}/vpnmgr.sh" | grep -c 'Update_Addon_Files "\$serverver"' || true)"
if [[ "$_uv_calls" -eq 2 ]]; then
    pass "Update_Version: both update paths call Update_Addon_Files"
else
    fail "Update_Version: expected 2 Update_Addon_Files calls, found ${_uv_calls}"
fi

if sed -n '/^if \[ -z "\$1" \]; then/,/^fi/p' "${REPO_ROOT}/vpnmgr.sh" | grep -q 'Sync_Addon_Files'; then
    pass "interactive startup calls Sync_Addon_Files"
else
    fail "interactive startup does not call Sync_Addon_Files"
fi

if grep -q "vpnmgr_www" "${REPO_ROOT}/.github/workflows/ci.yml" && grep -q "www/" "${REPO_ROOT}/.github/workflows/ci.yml"; then
    pass "ci.yml: version bump check covers WebUI files"
else
    fail "ci.yml: version bump check does not cover WebUI files"
fi

_SAF_EXTRACT="$(mktemp)"
sed -n '/^Update_Addon_Files(){/,/^}/p' "${REPO_ROOT}/vpnmgr.sh" > "$_SAF_EXTRACT"
sed -n '/^Sync_Addon_Files(){/,/^}/p' "${REPO_ROOT}/vpnmgr.sh" >> "$_SAF_EXTRACT"
# shellcheck source=/dev/null
. "$_SAF_EXTRACT"
rm -f "$_SAF_EXTRACT"

_SAF_DIR="$(mktemp -d)"
SCRIPT_NAME="vpnmgr"
SCRIPT_VERSION="v9.9.9"
SCRIPT_FILES_VERSION="${_SAF_DIR}/.files_version"
WARN=""
_SAF_LOG=""
_SAF_FAIL=""
Print_Output()      { :; }
Update_File()       { _SAF_LOG="${_SAF_LOG}js "; [[ "$_SAF_FAIL" != "js" ]]; }
Install_Providers() { _SAF_LOG="${_SAF_LOG}providers "; [[ "$_SAF_FAIL" != "providers" ]]; }

_SAF_LOG=""; Sync_Addon_Files || true
if [[ "$_SAF_LOG" == "js providers " && "$(cat "$SCRIPT_FILES_VERSION" 2>/dev/null)" == "v9.9.9" ]]; then
    pass "Sync_Addon_Files: no recorded version -> refreshes and records version"
else
    fail "Sync_Addon_Files: no recorded version (calls '${_SAF_LOG}')"
fi

_SAF_LOG=""; Sync_Addon_Files || true
if [[ -z "$_SAF_LOG" ]]; then
    pass "Sync_Addon_Files: recorded version matches -> no downloads"
else
    fail "Sync_Addon_Files: matching version still downloaded (calls '${_SAF_LOG}')"
fi

echo "v9.9.8" > "$SCRIPT_FILES_VERSION"
_SAF_LOG=""; Sync_Addon_Files || true
if [[ "$_SAF_LOG" == "js providers " && "$(cat "$SCRIPT_FILES_VERSION")" == "v9.9.9" ]]; then
    pass "Sync_Addon_Files: older recorded version -> refreshes"
else
    fail "Sync_Addon_Files: older recorded version (calls '${_SAF_LOG}')"
fi

for _saf_step in js providers; do
    echo "v9.9.8" > "$SCRIPT_FILES_VERSION"
    _SAF_FAIL="$_saf_step"
    if ! Sync_Addon_Files && [[ "$(cat "$SCRIPT_FILES_VERSION")" == "v9.9.8" ]]; then
        pass "Sync_Addon_Files: failed ${_saf_step} download -> version not recorded, retried next run"
    else
        fail "Sync_Addon_Files: failed ${_saf_step} download recorded as done"
    fi
done
_SAF_FAIL=""
rm -rf "$_SAF_DIR"

# ---------------------------------------------------------------------------
# Section 12: Searchable country/city picker (offline)
#
# The picker's matching (Picker_Filter) and key handling (Picker_HandleKey)
# do no terminal I/O, so they can be driven here with key tokens. The raw
# key reads and redraws in Picker_Select need a real terminal and are not
# covered. Same extraction approach as section 10.
# ---------------------------------------------------------------------------
section "12. Searchable country/city picker (offline)"

_PICK_EXTRACT="$(mktemp)"
sed -n '/^Validate_Number(){/,/^}/p' "${REPO_ROOT}/vpnmgr.sh" > "$_PICK_EXTRACT"
sed -n '/^### Searchable picker/,/^### End of searchable picker/p' "${REPO_ROOT}/vpnmgr.sh" >> "$_PICK_EXTRACT"
# shellcheck source=/dev/null
. "$_PICK_EXTRACT"
rm -f "$_PICK_EXTRACT"

_PICK_FIXTURE="$(printf '%s\n' "Albania" "Cote d'Ivoire" "New York" "Niger" "Nigeria" "St. John's (Antigua)" "Tunisia" "United Arab Emirates" "United Kingdom" "United States")"

assert_filter() {
    local desc="$1" query="$2" expected="$3" got
    PICK_QUERY="$query"
    got="$(printf '%s\n' "$_PICK_FIXTURE" | Picker_Filter | paste -sd'|' -)"
    if [[ "$got" == "$expected" ]]; then
        pass "$desc"
    else
        fail "$desc (expected '${expected}', got '${got}')"
    fi
}

# pick_run allow_blank token...  — a token is a key name, or a single character to type
pick_run() {
    PICK_LIST="$_PICK_FIXTURE"
    PICK_ALLOW_BLANK="$1"
    PICK_QUERY=""; PICK_MSG=""; PICK_DONE=""; PICK_RESULT=""
    shift
    Picker_Refilter
    local tok
    for tok in "$@"; do
        case "$tok" in
            TAB|BTAB|UP|DOWN|ENTER|ESC|EOF|BS) Picker_HandleKey "$tok" ;;
            *) Picker_HandleKey CHAR "$tok" ;;
        esac
    done
}

assert_pick() {
    local desc="$1" field="$2" expected="$3" got
    case "$field" in
        result) got="${PICK_DONE}:${PICK_RESULT}" ;;
        query)  got="$PICK_QUERY" ;;
        sel)    got="$PICK_SEL" ;;
        open)   got="${PICK_DONE:-open}:${PICK_MSG%% *}" ;;
    esac
    if [[ "$got" == "$expected" ]]; then
        pass "$desc"
    else
        fail "$desc (expected '${expected}', got '${got}')"
    fi
}

assert_filter "substring anywhere, list order kept" "uni" "Tunisia|United Arab Emirates|United Kingdom|United States"
assert_filter "more characters narrow the list"    "united k" "United Kingdom"
assert_filter "case-insensitive"                   "NEW YORK" "New York"
assert_filter "spaces ignored"                     "newyork"  "New York"
assert_filter "punctuation ignored"                "st johns" "St. John's (Antigua)"
assert_filter "apostrophe in name ignored"         "cote d"   "Cote d'Ivoire"
assert_filter "regex characters are literal"       "n.w"      ""
assert_filter "backslash is literal"               'n\w'      ""
assert_filter "no match gives empty list"          "atlantis" ""
assert_filter "empty query returns everything"     ""         "$(printf '%s\n' "$_PICK_FIXTURE" | paste -sd'|' -)"

pick_run false u n i TAB TAB ENTER
assert_pick "Tab moves down the matches" result "ok:United Arab Emirates"
pick_run false u n i TAB TAB TAB TAB TAB
assert_pick "Tab wraps to the first match" sel "1"
assert_pick "Tab leaves the query unchanged" query "uni"
pick_run false u n i BTAB ENTER
assert_pick "Shift+Tab wraps to the last match" result "ok:United States"
pick_run false TAB ENTER
assert_pick "Tab on a blank query browses the full list" result "ok:Albania"
pick_run false DOWN DOWN UP ENTER
assert_pick "arrow keys move the highlight" result "ok:Albania"
pick_run false u n i TAB TAB t e d
assert_pick "typing after Tab edits the query" query "united"
assert_pick "typing after Tab clears the highlight" sel "0"
pick_run false u n i x BS TAB ENTER
assert_pick "Backspace broadens the matches" result "ok:Tunisia"
pick_run false t u n ENTER
assert_pick "Enter accepts a unique partial match" result "ok:Tunisia"
pick_run false n i g e r ENTER
assert_pick "Enter accepts an exact name that prefixes another" result "ok:Niger"
pick_run false u n i ENTER
assert_pick "Enter on an ambiguous query stays open" open "open:Multiple"
pick_run false z z ENTER
assert_pick "Enter on an unmatched query stays open" open "open:No"
pick_run false ENTER
assert_pick "blank Enter is rejected when a choice is required" open "open:A"
pick_run true ENTER
assert_pick "blank Enter means no preference when allowed" result "ok:"
pick_run true TAB ENTER
assert_pick "a highlighted name is chosen even with a blank query" result "ok:Albania"
pick_run true TAB BS ENTER
assert_pick "editing the query drops the highlight before a blank Enter" result "ok:"
pick_run false u n ESC
assert_pick "Esc cancels" result "cancel:"

# ---------------------------------------------------------------------------
# Section 13: Install source recording (offline)
#
# "vpnmgr develop" pins the install to the commit the branch resolves to and
# records "<branch>@<commit>" for the CLI header and WebUI; installs from main
# clear it. Same extraction approach as section 10, with curl stubbed and the
# custom settings file redirected to a temp file.
# ---------------------------------------------------------------------------
section "13. Install source recording (offline)"

_IS_DIR="$(mktemp -d)"
_IS_EXTRACT="$(mktemp)"
for _is_fn in Set_Version_Custom_Settings Pin_Script_Repo Record_Install_Source; do
    sed -n "/^${_is_fn}(){/,/^}/p" "${REPO_ROOT}/vpnmgr.sh"
done | sed "s|/usr/sbin/curl|_is_curl|g; s|/jffs/addons/custom_settings.txt|${_IS_DIR}/custom_settings.txt|g" > "$_IS_EXTRACT"
# shellcheck source=/dev/null
. "$_IS_EXTRACT"
rm -f "$_IS_EXTRACT"

SCRIPT_NAME="vpnmgr"
SCRIPT_SOURCE_FILE="${_IS_DIR}/.install_source"
_IS_SETTINGS="${_IS_DIR}/custom_settings.txt"
_IS_REPLY=""
_is_curl() { printf '%s' "$_IS_REPLY"; }
Print_Output() { :; }
printf 'vpnmgr_version_local v9.9.9\nother_addon_setting 1\n' > "$_IS_SETTINGS"

_IS_REPLY="0123456789abcdef0123456789abcdef01234567"
Pin_Script_Repo develop
assert_eq "Pin_Script_Repo: downloads pinned to the resolved commit" \
    "https://raw.githubusercontent.com/h0me5k1n/vpnmgr/0123456789abcdef0123456789abcdef01234567" "$SCRIPT_REPO"
assert_eq "Pin_Script_Repo: source is branch@short commit" "develop@0123456" "$SCRIPT_SOURCE"

Record_Install_Source
assert_eq "Record_Install_Source: develop install recorded for the CLI header" \
    "develop@0123456" "$(cat "$SCRIPT_SOURCE_FILE" 2>/dev/null)"
assert_eq "Record_Install_Source: develop install recorded for the WebUI" \
    "vpnmgr_version_source develop@0123456" "$(grep '^vpnmgr_version_source ' "$_IS_SETTINGS")"
assert_eq "Record_Install_Source: other settings untouched" \
    "2" "$(grep -c '^vpnmgr_version_local v9.9.9$\|^other_addon_setting 1$' "$_IS_SETTINGS")"

# The WebUI settings merge skips keys containing "version"; the source key
# must be one of them or it would be merged into the config and deleted.
if grep 'vpnmgr_' "$_IS_SETTINGS" | grep -v 'version' | grep -q 'source'; then
    fail "vpnmgr_version_source would be picked up by Conf_FromSettings"
else
    pass "vpnmgr_version_source is left alone by Conf_FromSettings"
fi

Record_Install_Source
assert_eq "Record_Install_Source: re-recording does not duplicate the setting" \
    "1" "$(grep -c '^vpnmgr_version_source ' "$_IS_SETTINGS")"

_IS_REPLY='{"message": "API rate limit exceeded"}'
Pin_Script_Repo develop
assert_eq "Pin_Script_Repo: lookup failure falls back to the branch" \
    "https://raw.githubusercontent.com/h0me5k1n/vpnmgr/develop" "$SCRIPT_REPO"
assert_eq "Pin_Script_Repo: lookup failure is shown as unknown" "develop@unknown" "$SCRIPT_SOURCE"

_IS_REPLY="89abcdef0123456789abcdef0123456789abcdef"
Pin_Script_Repo main
Record_Install_Source
if [[ ! -f "$SCRIPT_SOURCE_FILE" ]] && ! grep -q '^vpnmgr_version_source ' "$_IS_SETTINGS"; then
    pass "Record_Install_Source: install from main clears the record"
else
    fail "Record_Install_Source: install from main left a record behind"
fi

SCRIPT_SOURCE=""
printf 'develop@0123456\n' > "$SCRIPT_SOURCE_FILE"
Record_Install_Source
if [[ ! -f "$SCRIPT_SOURCE_FILE" ]]; then
    pass "Record_Install_Source: plain update (no pinned source) clears the record"
else
    fail "Record_Install_Source: plain update left a stale record"
fi
rm -rf "$_IS_DIR"

# ---------------------------------------------------------------------------
# Section 14: Changelog
#
# The release workflow publishes the current SCRIPT_VERSION's CHANGELOG.md
# section as the GitHub release notes, so that section must exist before the
# version bump reaches main.
# ---------------------------------------------------------------------------
section "14. Changelog"

_cl_version=$(grep -m1 'SCRIPT_VERSION=' "${REPO_ROOT}/vpnmgr.sh" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
if _cl_notes=$(sh "${REPO_ROOT}/scripts/changelog-notes.sh" "$_cl_version" 2>&1); then
    pass "CHANGELOG.md has entries for ${_cl_version}"
    if grep -q '^## ' <<< "$_cl_notes"; then
        fail "CHANGELOG.md: ${_cl_version} notes run into another version's section"
    else
        pass "CHANGELOG.md: ${_cl_version} notes stop at the next section"
    fi
else
    fail "CHANGELOG.md has no entries for ${_cl_version} — add them before bumping SCRIPT_VERSION"
fi
# "Unreleased" exists only while it has entries; an empty one directly above
# the latest release reads as if that release were unreleased.
if ! grep -q '^## Unreleased$' "${REPO_ROOT}/CHANGELOG.md"; then
    pass "CHANGELOG.md: no Unreleased section (nothing pending)"
elif sh "${REPO_ROOT}/scripts/changelog-notes.sh" Unreleased >/dev/null 2>&1; then
    pass "CHANGELOG.md: Unreleased section has entries"
else
    fail "CHANGELOG.md: empty '## Unreleased' heading — remove it, or add the entries it is for"
fi

# ---------------------------------------------------------------------------
# Section 15: Firmware compatibility consumers
# ---------------------------------------------------------------------------
section "15. Firmware compatibility consumers (offline)"

if bash "${REPO_ROOT}/scripts/firmware-compat-test.sh"; then
    pass "Firmware compatibility: routing, retry and custom-options consumers"
else
    fail "Firmware compatibility: routing, retry and custom-options consumers"
fi

# ---------------------------------------------------------------------------
# Section 16: CLI WebUI URL lookup (offline)
# ---------------------------------------------------------------------------
section "16. CLI WebUI URL lookup (offline)"

if bash "${REPO_ROOT}/scripts/webui-url-test.sh"; then
    pass "Get_WebUI_URL: resolves the active menu-tree entry and formats its URL"
else
    fail "Get_WebUI_URL: resolves the active menu-tree entry and formats its URL"
fi

# Section 17: Uninstall removes per-client schedules (offline)
#
# ScheduleVPN adds vpnmgr_VPN<n> cron jobs plus services-start lines that
# recreate them; Auto_Cron/Auto_Startup don't touch either. CancelScheduleVPN
# is extracted with its hard-coded paths pointed at temp files.
# ---------------------------------------------------------------------------
section "17. Uninstall removes per-client schedules (offline)"

if sed -n '/^Menu_Uninstall(){/,/^}/p' "${REPO_ROOT}/vpnmgr.sh" | grep -q 'CancelScheduleVPN "\$i"'; then
    pass "Menu_Uninstall: cancels per-client schedules"
else
    fail "Menu_Uninstall: does not call CancelScheduleVPN"
fi

_CSV_DIR="$(mktemp -d)"
_CSV_EXTRACT="${_CSV_DIR}/extract.sh"
sed -n '/^CancelScheduleVPN(){/,/^}/p' "${REPO_ROOT}/vpnmgr.sh" \
    | sed "s~/jffs/scripts/services-start~${_CSV_DIR}/services-start~g" > "$_CSV_EXTRACT"
# shellcheck source=/dev/null
. "$_CSV_EXTRACT"

SCRIPT_NAME="vpnmgr"
SCRIPT_CONF="${_CSV_DIR}/config"
_CSV_CRU=""
Print_Output() { :; }
cru() {
    case "$1" in
        l) printf '%s\n' "0 4 * * 1 /jffs/scripts/vpnmgr updatevpn 2 #vpnmgr_VPN2#" ;;
        d) _CSV_CRU="${_CSV_CRU}$2 " ;;
    esac
}

printf 'vpn2_schenabled=true\n' > "$SCRIPT_CONF"
printf '%s\n' '#!/bin/sh' \
    'cru a vpnmgr_VPN2 "0 4 * * 1 /jffs/scripts/vpnmgr updatevpn 2" # vpnmgr' \
    'other-addon startup # other' > "${_CSV_DIR}/services-start"
CancelScheduleVPN 2
if [[ "$_CSV_CRU" == "vpnmgr_VPN2 " ]] \
    && ! grep -q 'vpnmgr_VPN2' "${_CSV_DIR}/services-start" \
    && grep -q 'other-addon' "${_CSV_DIR}/services-start" \
    && grep -q 'vpn2_schenabled=false' "$SCRIPT_CONF"; then
    pass "CancelScheduleVPN: removes the cron job and only its services-start line"
else
    fail "CancelScheduleVPN: cron deletes '${_CSV_CRU}', services-start: $(tr '\n' '|' < "${_CSV_DIR}/services-start")"
fi

rm -f "${_CSV_DIR}/services-start"
if [[ -z "$(CancelScheduleVPN 2 2>&1)" ]]; then
    pass "CancelScheduleVPN: no services-start file -> no errors"
else
    fail "CancelScheduleVPN: errors when services-start is missing"
fi
unset -f cru
rm -rf "$_CSV_DIR"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo ""
echo -e "${BOLD}─────────────────────────────────────────${NC}"
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}All ${TOTAL} tests passed.${NC}"
else
    echo -e "${RED}${BOLD}${FAIL} of ${TOTAL} tests failed.${NC}"
fi
echo -e "${BOLD}─────────────────────────────────────────${NC}"
echo ""

[[ $FAIL -eq 0 ]]
