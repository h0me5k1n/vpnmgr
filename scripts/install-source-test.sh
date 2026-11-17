#!/bin/sh
# Actual install/update/reentry clauses with fake HTTP and owned router paths.
# No full manager execution, network, system dependencies or live router access.
set -eu
ROOT="$(CDPATH='' cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
export DIRECT_FIXTURES="$TEST_DIR/fixtures" DIRECT_TEST_ROOT="$TEST_DIR/normal"
mkdir -p "$DIRECT_FIXTURES" "$DIRECT_TEST_ROOT/scripts"
SHA_B=123456789abcdef0123456789abcdef012345678
SHA_C=23456789abcdef0123456789abcdef0123456789
export SHA_B SHA_C
for fn in Unpinned_Script_Repo Pin_Script_Repo Ensure_Update_Source Script_Source_Identity \
 Load_Installed_Source Resolve_Installed_Source Configure_Test_Providers Provider_WebUI_Enabled \
 Select_Install_Source Bootstrap_Install Record_Install_Source Download_File Download_Asset \
 Update_File Install_Providers Update_Addon_Files Sync_Addon_Files Update_Check Update_Version \
 Create_Dirs Create_Symlinks Runtime_Init Menu_Install; do
 sed -n "/^${fn}(){/,/^}/p" "$ROOT/vpnmgr.sh"
done | sed 's|/usr/sbin/curl|fixture_curl|g;s|/jffs/scripts|$DIRECT_TEST_ROOT/scripts|g;s|/tmp/menuTree.js|$DIRECT_TEST_ROOT/menuTree.js|g' > "$DIRECT_FIXTURES/functions"
cat > "$DIRECT_FIXTURES/prefix" <<'SCRIPT'
#!/bin/sh
# h0me5k1n attribution retained in the controlled fixture.
# Match production shell flags, including optional CLI arguments and explicit
# error propagation rather than implicit errexit.
BUILD_ID=A
SCRIPT_NAME=vpnmgr; SCRIPT_VERSION=v1.0.0
SCRIPT_REPOSITORY=fixture-owner/vpnmgr
SCRIPT_BRANCH="${DIRECT_BRANCH:-topic/fixture}"
SCRIPT_BRANCH_OVERRIDE="${DIRECT_OVERRIDE-topic/fixture}"
SCRIPT_REVISION=''; SCRIPT_SOURCE=''; SCRIPT_UPDATE_READY=false
SCRIPT_DIR="$DIRECT_TEST_ROOT/addon"; SCRIPT_CONF="$SCRIPT_DIR/config"
SCRIPT_WWW_DIR="$SCRIPT_DIR/www"; PROVIDERS_DIR="$SCRIPT_DIR/providers"
OVPN_ARCHIVE_DIR="$SCRIPT_DIR/ovpn"
SCRIPT_WEB_DIR="$DIRECT_TEST_ROOT/web"; SCRIPT_WEBPAGE_DIR="$DIRECT_TEST_ROOT/pages"
SCRIPT_SOURCE_FILE="$SCRIPT_DIR/.install_source"; SCRIPT_SOURCE_REVISION_FILE="$SCRIPT_DIR/.install_revision"
SCRIPT_FILES_SOURCE="$SCRIPT_DIR/.files_source"; SCRIPT_FILES_VERSION="$SCRIPT_DIR/.files_version"
SCRIPT_TEST_PROVIDER_FILE="$SCRIPT_DIR/.test_providers"; VPNMGR_RUNTIME_DIR="$DIRECT_TEST_ROOT/runtime"
PASS=; WARN=; ERR=; CRIT=; BOLD=; CLEARFORMAT=
. "$DIRECT_FIXTURES/functions"
printf '%s\n' "$BUILD_ID" >> "$DIRECT_TEST_ROOT/starts"
mkdir -p "$SCRIPT_WEB_DIR" "$SCRIPT_WEBPAGE_DIR"
Print_Output(){ :; }; Set_Version_Custom_Settings(){ [ "$1" != source ] || printf '%s' "$2" > "$DIRECT_TEST_ROOT/label"; }
Check_Lock(){ touch "$DIRECT_TEST_ROOT/lock" "$DIRECT_TEST_ROOT/lock-acquired"; }
Clear_Lock(){ rm -f "$DIRECT_TEST_ROOT/lock"; }
ScriptHeader(){ :; }; sleep(){ :; }; Check_Requirements(){ :; }; PressEnter(){ :; }
NTP_Ready(){ :; }; Entware_Ready(){ :; }
Conf_Exists(){ [ -f "$SCRIPT_CONF" ] || printf 'vpn1_managed=false\n' > "$SCRIPT_CONF"; }
Auto_Cron(){ :; }; Auto_Startup(){ :; }; Auto_ServiceEvent(){ :; }; Shortcut_Script(){ :; }
Refresh_Provider_Cache(){ :; }; opkg(){ :; }
MainMenu(){ printf '%s' "$BUILD_ID" > "$DIRECT_TEST_ROOT/ran"; }
Mount_WebUI(){ cp "$SCRIPT_DIR/vpnmgr_www.asp" "$SCRIPT_WEBPAGE_DIR/user1.asp"; }
Get_WebUI_Page(){ MyPage=user1.asp; }
fixture_curl(){
 _out=; _url=; _prev=
 for _arg do
  [ "$_prev" != -o ] || _out="$_arg"
  case "$_arg" in https://*) _url="$_arg" ;; esac
  _prev="$_arg"
 done
 printf '%s\n' "$_url" >> "$DIRECT_TEST_ROOT/requests"
 case "$_url" in
  https://api.github.com/*)
   [ "${DIRECT_API_FAIL:-no}" != yes ] || return 22
   cat "$DIRECT_TEST_ROOT/tip"
   printf '%s' "$SHA_C" > "$DIRECT_TEST_ROOT/tip"
   return 0 ;;
 esac
 case "$_url" in
  */"$SHA_B"/vpnmgr.sh)
   [ ! -f "$DIRECT_TEST_ROOT/fail-main" ] || return 22
   _body="$(cat "$DIRECT_FIXTURES/B")"
   [ ! -f "$DIRECT_TEST_ROOT/fail-syntax" ] || _body='# h0me5k1n
if'
   [ ! -f "$DIRECT_TEST_ROOT/fail-attribution" ] || _body='#!/bin/sh
exit 0' ;;
  */"$SHA_C"/*) return 22 ;;
  */vpnmgr.sh) _body="$(cat "$DIRECT_FIXTURES/${DIRECT_BRANCH_BODY:-A}")" ;;
  */vpnmgr_www.js)
   [ ! -f "$DIRECT_TEST_ROOT/fail-js" ] || return 22
   _body="JavaScript from $_url" ;;
  */vpnmgr_www.asp) _body='constant ASP fixture' ;;
  */providers/provider_nordvpn.sh)
   _body='#!/bin/sh
# NordVPN fixture
# Status: UNTESTED
# Display: NordVPN' ;;
  *) _body="Asset from $_url" ;;
 esac
 if [ -n "$_out" ]; then printf '%s\n' "$_body" > "$_out"; else printf '%s\n' "$_body"; fi
}
SCRIPT
cp "$DIRECT_FIXTURES/prefix" "$DIRECT_FIXTURES/A"
sed -n '/^if \[ -z "\$1" \]; then/,/^fi$/p' "$ROOT/vpnmgr.sh" >> "$DIRECT_FIXTURES/A"
printf 'case "$1" in\n' >> "$DIRECT_FIXTURES/A"
for entry in install forceupdate postupdate develop stable; do
 sed -n "/^[[:space:]]*${entry})/,/^[[:space:]]*;;/p" "$ROOT/vpnmgr.sh" >> "$DIRECT_FIXTURES/A"
done
printf 'esac\n' >> "$DIRECT_FIXTURES/A"
sed 's/^BUILD_ID=A$/BUILD_ID=B/' "$DIRECT_FIXTURES/A" > "$DIRECT_FIXTURES/B"
# Use the fixture's HTTP boundary for the same direct-download/chmod/install flow.
direct_install(){
 cp "$DIRECT_FIXTURES/${DIRECT_BRANCH_BODY:-A}" "$DIRECT_TEST_ROOT/scripts/vpnmgr"
 chmod 0755 "$DIRECT_TEST_ROOT/scripts/vpnmgr"
 "$DIRECT_TEST_ROOT/scripts/vpnmgr" install
}
fail(){ printf 'FAIL: %s\n' "$*" >&2; exit 1; }
eq(){ [ "$2" = "$3" ] || fail "$1 expected <$2>, got <$3>"; }
unset VPNMGR_INSTALL_SHA VPNMGR_INSTALL_BRANCH VPNMGR_TEST_PROVIDERS
printf '%s' "$SHA_B" > "$DIRECT_TEST_ROOT/tip"
direct_install
eq 'candidate script actually ran' B "$(cat "$DIRECT_TEST_ROOT/ran")"
cmp -s "$DIRECT_TEST_ROOT/scripts/vpnmgr" "$DIRECT_FIXTURES/B" || fail 'installed main not candidate B'
eq 'one lookup despite branch advancing to C' 1 "$(grep -c '^https://api.github.com/' "$DIRECT_TEST_ROOT/requests")"
if grep '^https://raw.githubusercontent.com/' "$DIRECT_TEST_ROOT/requests" | grep -v "/$SHA_B/" >/dev/null; then fail 'install mixed source revisions'; fi
eq 'main provenance' "fixture-owner/vpnmgr|topic/fixture|$SHA_B" "$(cat "$DIRECT_TEST_ROOT/addon/.install_revision")"
eq 'asset provenance' "fixture-owner/vpnmgr|topic/fixture|$SHA_B" "$(cat "$DIRECT_TEST_ROOT/addon/.files_source")"
grep -qx 'nordvpn|NordVPN' "$DIRECT_TEST_ROOT/addon/providers_list" || fail 'normal test install hid NordVPN'
grep -qx '# Status: UNTESTED' "$DIRECT_TEST_ROOT/addon/providers/provider_nordvpn.sh" || fail 'provider status promoted'
cmp -s "$DIRECT_TEST_ROOT/addon/vpnmgr_www.js" "$DIRECT_TEST_ROOT/web/vpnmgr_www.js" || fail 'served JS differs'
cmp -s "$DIRECT_TEST_ROOT/addon/vpnmgr_www.asp" "$DIRECT_TEST_ROOT/pages/user1.asp" || fail 'served ASP differs'
# Equal main bytes do not require another exec, and still need no internal vars.
export DIRECT_BRANCH_BODY=B
printf '%s' "$SHA_B" > "$DIRECT_TEST_ROOT/tip"
direct_install
eq 'equal-byte path starts only once' 3 "$(wc -l < "$DIRECT_TEST_ROOT/starts" | tr -d ' ')"
unset DIRECT_BRANCH_BODY
# Existing branch-switch commands honor the temporary test lock.
printf '%s' "$SHA_B" > "$DIRECT_TEST_ROOT/tip"
: > "$DIRECT_TEST_ROOT/requests"
"$DIRECT_TEST_ROOT/scripts/vpnmgr" develop
grep -q '/commits/topic/fixture$' "$DIRECT_TEST_ROOT/requests" || fail 'test develop command escaped feature branch'
eq 'temporary branch lock preserved' "fixture-owner/vpnmgr|topic/fixture|$SHA_B" "$(cat "$DIRECT_TEST_ROOT/addon/.install_revision")"
# A staged fetch failure happens before lock/config/asset writes.
for rejection in main syntax attribution; do
 export DIRECT_TEST_ROOT="$TEST_DIR/reject-$rejection"
 mkdir -p "$DIRECT_TEST_ROOT/scripts"; touch "$DIRECT_TEST_ROOT/fail-$rejection"
 printf '%s' "$SHA_B" > "$DIRECT_TEST_ROOT/tip"
 if direct_install; then fail 'invalid staged script accepted'; fi
 [ ! -d "$DIRECT_TEST_ROOT/addon" ] && [ ! -f "$DIRECT_TEST_ROOT/lock-acquired" ] || fail 'install mutated state before verifying main'
 cmp -s "$DIRECT_TEST_ROOT/scripts/vpnmgr" "$DIRECT_FIXTURES/A" || fail 'rejected candidate replaced initial script'
done
export DIRECT_TEST_ROOT="$TEST_DIR/reject-sha" VPNMGR_INSTALL_SHA=invalid
mkdir -p "$DIRECT_TEST_ROOT/scripts"
if direct_install; then fail 'invalid supplied SHA accepted by entry point'; fi
[ ! -f "$DIRECT_TEST_ROOT/requests" ] && [ ! -f "$DIRECT_TEST_ROOT/lock-acquired" ] || fail 'invalid supplied SHA reached downloads/lock'
unset VPNMGR_INSTALL_SHA
# A failed asset refresh retains new main provenance; reentry repairs B, not C.
export DIRECT_TEST_ROOT="$TEST_DIR/asset-failure"
mkdir -p "$DIRECT_TEST_ROOT/scripts"; touch "$DIRECT_TEST_ROOT/fail-js"
mkdir -p "$DIRECT_TEST_ROOT/addon"
printf '%s\n' 'fixture-owner/vpnmgr|topic/fixture|0123456789abcdef0123456789abcdef01234567' > "$DIRECT_TEST_ROOT/addon/.install_revision"
cp "$DIRECT_TEST_ROOT/addon/.install_revision" "$DIRECT_TEST_ROOT/addon/.files_source"
printf '%s' "$SHA_B" > "$DIRECT_TEST_ROOT/tip"
if direct_install; then fail 'failed dependency accepted'; fi
[ ! -f "$DIRECT_TEST_ROOT/lock" ] || fail 'failed dependency retained install lock'
eq 'new main retained after asset failure' "fixture-owner/vpnmgr|topic/fixture|$SHA_B" "$(cat "$DIRECT_TEST_ROOT/addon/.install_revision")"
eq 'failed dependencies retained old completion' 'fixture-owner/vpnmgr|topic/fixture|0123456789abcdef0123456789abcdef01234567' "$(cat "$DIRECT_TEST_ROOT/addon/.files_source")"
rm -f "$DIRECT_TEST_ROOT/fail-js"
: > "$DIRECT_TEST_ROOT/requests"
"$DIRECT_TEST_ROOT/scripts/vpnmgr" postupdate
if grep -v "/$SHA_B/" "$DIRECT_TEST_ROOT/requests" >/dev/null; then fail 'repair changed verified candidate'; fi
# Ordinary builds alone retain a visibly unknown raw-branch compatibility mode.
export DIRECT_TEST_ROOT="$TEST_DIR/fallback" DIRECT_OVERRIDE='' DIRECT_BRANCH=main DIRECT_API_FAIL=yes
mkdir -p "$DIRECT_TEST_ROOT/scripts"
direct_install
eq 'ordinary unknown provenance' 'fixture-owner/vpnmgr|main|unknown' "$(cat "$DIRECT_TEST_ROOT/addon/.install_revision")"
eq 'ordinary main unknown label' main@unknown "$(cat "$DIRECT_TEST_ROOT/label")"
eq 'unpinned install did not loop' 1 "$(wc -l < "$DIRECT_TEST_ROOT/starts" | tr -d ' ')"
: > "$DIRECT_TEST_ROOT/requests"
"$DIRECT_TEST_ROOT/scripts/vpnmgr" postupdate
[ ! -s "$DIRECT_TEST_ROOT/requests" ] || fail 'healthy unknown-source reentry looked up another revision'
"$DIRECT_TEST_ROOT/scripts/vpnmgr" forceupdate
eq 'fallback update preserved unknown provenance' 'fixture-owner/vpnmgr|main|unknown' "$(cat "$DIRECT_TEST_ROOT/addon/.install_revision")"
eq 'fallback update/reentry one lookup' 1 "$(grep -c '^https://api.github.com/' "$DIRECT_TEST_ROOT/requests")"
# After TEMP removal, real CLI switching retains upstream branch semantics.
export DIRECT_API_FAIL=no
printf '%s' "$SHA_B" > "$DIRECT_TEST_ROOT/tip"
: > "$DIRECT_TEST_ROOT/requests"
"$DIRECT_TEST_ROOT/scripts/vpnmgr" develop
grep -q '/commits/develop$' "$DIRECT_TEST_ROOT/requests" || fail 'ordinary develop command selected wrong branch'
eq 'develop metadata' "fixture-owner/vpnmgr|develop|$SHA_B" "$(cat "$DIRECT_TEST_ROOT/addon/.install_revision")"
printf '%s' "$SHA_B" > "$DIRECT_TEST_ROOT/tip"
: > "$DIRECT_TEST_ROOT/requests"
"$DIRECT_TEST_ROOT/scripts/vpnmgr" stable
grep -q '/commits/main$' "$DIRECT_TEST_ROOT/requests" || fail 'ordinary stable command selected wrong branch'
eq 'stable metadata' "fixture-owner/vpnmgr|main|$SHA_B" "$(cat "$DIRECT_TEST_ROOT/addon/.install_revision")"
[ ! -s "$DIRECT_TEST_ROOT/label" ] || fail 'stable left stale branch label'
printf 'Normal direct install, revision race, visibility, failure repair and ordinary fallback checks passed (offline).\n'
