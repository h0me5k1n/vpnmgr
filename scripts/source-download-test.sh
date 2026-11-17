#!/bin/sh
# Real download/source functions with inert GitHub and router file boundaries.
# shellcheck disable=SC2034
set -eu
if [ -n "${VPNMGR_TEST_REEXEC_FILE:-}" ]; then
	# shellcheck disable=SC1090
	. "$VPNMGR_TEST_FUNCTIONS"
	Print_Output(){ :; }
	Resolve_Installed_Source || exit 1
	printf '%s|%s|%s' "$VPNMGR_INSTALL_SHA" "$VPNMGR_INSTALL_BRANCH" "$SCRIPT_REVISION" > "$VPNMGR_TEST_REEXEC_FILE"
	exit 0
fi
ROOT="$(CDPATH='' cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
mkdir -p "$TEST_DIR/addon/www" "$TEST_DIR/addon/providers" "$TEST_DIR/web" "$TEST_DIR/scripts"
for fn in Unpinned_Script_Repo Pin_Script_Repo Ensure_Update_Source Script_Source_Identity Load_Installed_Source \
	Resolve_Installed_Source Configure_Test_Providers Provider_WebUI_Enabled Select_Install_Source Bootstrap_Install \
	Record_Install_Source Download_File Download_Asset Update_File Install_Providers \
	Update_Addon_Files Sync_Addon_Files Update_Check Update_Version Create_Dirs Create_Symlinks Runtime_Init Menu_Install; do
	sed -n "/^${fn}(){/,/^}/p" "$ROOT/vpnmgr.sh"
done | sed "s|/usr/sbin/curl|fixture_curl|g;s|/jffs/scripts|$TEST_DIR/scripts|g;s|/tmp/menuTree.js|\"$TEST_DIR/menuTree.js\"|g" > "$TEST_DIR/functions"
. "$TEST_DIR/functions"
SCRIPT_NAME=vpnmgr; SCRIPT_VERSION=v1.0.0
SCRIPT_REPOSITORY=fixture-owner/vpnmgr; SCRIPT_BRANCH=main; SCRIPT_BRANCH_OVERRIDE=""
SCRIPT_REVISION=""; SCRIPT_SOURCE=""; SCRIPT_UPDATE_READY=false
SCRIPT_DIR="$TEST_DIR/addon"; SCRIPT_WWW_DIR="$SCRIPT_DIR/www"; PROVIDERS_DIR="$SCRIPT_DIR/providers"
SCRIPT_WEB_DIR="$TEST_DIR/web"; SCRIPT_WEBPAGE_DIR="$TEST_DIR/web"
SCRIPT_SOURCE_FILE="$SCRIPT_DIR/.install_source"; SCRIPT_SOURCE_REVISION_FILE="$SCRIPT_DIR/.install_revision"
SCRIPT_FILES_SOURCE="$SCRIPT_DIR/.files_source"; SCRIPT_FILES_VERSION="$SCRIPT_DIR/.files_version"
SCRIPT_TEST_PROVIDER_FILE="$SCRIPT_DIR/.test_providers"
PASS=""; WARN=""; ERR=""; CRIT=""; BOLD=""; CLEARFORMAT=""
SHA_A=0123456789abcdef0123456789abcdef01234567
SHA_B=123456789abcdef0123456789abcdef012345678
SHA_C=23456789abcdef0123456789abcdef0123456789
FIXTURE_SHA="$SHA_A"; FIXTURE_API_FAIL=false; FIXTURE_FAIL=""
FIXTURE_SCRIPT='# h0me5k1n attribution
SCRIPT_VERSION="v1.0.0"'
REQUESTS="$TEST_DIR/requests"; : > "$REQUESTS"
Print_Output(){ printf '%s\n' "$2" >> "$TEST_DIR/messages"; }
Set_Version_Custom_Settings(){ :; }
Clear_Lock(){ :; }
PressEnter(){ :; }
Mount_WebUI(){ cp "$SCRIPT_DIR/vpnmgr_www.asp" "$TEST_DIR/served.asp"; }
Get_WebUI_Page(){ MyPage=user1.asp; }
fixture_curl(){
	_fc_url=""; _fc_out=""; _fc_prev=""
	for _fc_arg do
		[ "$_fc_prev" != -o ] || _fc_out="$_fc_arg"
		case "$_fc_arg" in https://*) _fc_url="$_fc_arg" ;; esac
		_fc_prev="$_fc_arg"
	done
	printf '%s\n' "$_fc_url" >> "$REQUESTS"
	case "$_fc_url" in
		https://api.github.com/*) printf '%s' "$FIXTURE_SHA"; [ "$FIXTURE_API_FAIL" = false ]; return $? ;;
	esac
	case "$_fc_url" in *"$FIXTURE_FAIL"*) [ -z "$FIXTURE_FAIL" ] || return 1 ;; esac
	case "$_fc_url" in
		*/vpnmgr.sh) _fc_content="$FIXTURE_SCRIPT" ;;
		*/vpnmgr_www.asp) _fc_content='constant fixture ASP' ;;
		*) _fc_content="asset from $_fc_url" ;;
	esac
	if [ -n "$_fc_out" ]; then printf '%s\n' "$_fc_content" > "$_fc_out"; else printf '%s\n' "$_fc_content"; fi
}
fail(){ printf 'FAIL: %s\n' "$*" >&2; exit 1; }
eq(){ [ "$2" = "$3" ] || fail "$1 expected <$2>, got <$3>"; }
none(){ [ ! -s "$REQUESTS" ] || fail "$1 unexpectedly fetched files"; }

# Bootstrap receives an already-resolved commit; no independent branch lookup.
Pin_Script_Repo topic/fixture "$SHA_A"
none 'supplied SHA'
eq 'repository' "https://raw.githubusercontent.com/fixture-owner/vpnmgr/$SHA_A" "$SCRIPT_REPO"
Record_Install_Source
eq 'full installed provenance' "fixture-owner/vpnmgr|topic/fixture|$SHA_A" "$(cat "$SCRIPT_SOURCE_REVISION_FILE")"
SCRIPT_REVISION="$SHA_B"; SCRIPT_BRANCH=main
Load_Installed_Source
eq 'repair uses installed revision' "$SHA_A" "$SCRIPT_REVISION"
eq 'repair is not an update candidate' false "$SCRIPT_UPDATE_READY"
printf '%s\n' "$SCRIPT_VERSION" > "$SCRIPT_FILES_VERSION"
Script_Source_Identity > "$SCRIPT_FILES_SOURCE"
Sync_Addon_Files
none 'healthy installed-source repair'

# A semantic-version mismatch remains a refresh trigger with the same source.
printf 'v0.9.0\n' > "$SCRIPT_FILES_VERSION"
Sync_Addon_Files
eq 'version completion marker' "$SCRIPT_VERSION" "$(cat "$SCRIPT_FILES_VERSION")"
[ -s "$REQUESTS" ] || fail 'version mismatch did not refresh assets'
: > "$REQUESTS"

# Same version, new installed source: refresh every dependent file at that SHA.
Pin_Script_Repo topic/fixture "$SHA_B"; Record_Install_Source
Sync_Addon_Files
eq 'source completion marker' "$(Script_Source_Identity)" "$(cat "$SCRIPT_FILES_SOURCE")"
cmp -s "$SCRIPT_DIR/vpnmgr_www.js" "$SCRIPT_WEB_DIR/vpnmgr_www.js" || fail 'saved/served JavaScript diverged'
if grep -v "/$SHA_B/" "$REQUESTS" >/dev/null; then fail 'asset refresh mixed source revisions'; fi
grep -q 'www/jquery.js' "$REQUESTS" && grep -q 'www/detect.js' "$REQUESTS" &&
	grep -q 'vpnmgr_www.asp' "$REQUESTS" && grep -q 'vpnmgr_www.js' "$REQUESTS" &&
	grep -q 'providers/provider_nordvpn.sh' "$REQUESTS" || fail 'asset/provider download entry omitted'

# A rejected download preserves its previous file and does not mark completion.
cp "$SCRIPT_FILES_SOURCE" "$TEST_DIR/completion-before"
cp "$PROVIDERS_DIR/provider_nordvpn.sh" "$TEST_DIR/provider-before"
Pin_Script_Repo topic/fixture "$SHA_C"; Record_Install_Source
FIXTURE_FAIL=providers/provider_nordvpn.sh
if Sync_Addon_Files; then fail 'failed provider download accepted'; fi
cmp -s "$TEST_DIR/completion-before" "$SCRIPT_FILES_SOURCE" || fail 'failed refresh marked complete'
cmp -s "$TEST_DIR/provider-before" "$PROVIDERS_DIR/provider_nordvpn.sh" || fail 'failed download replaced installed provider'
FIXTURE_FAIL=""; : > "$REQUESTS"
Sync_Addon_Files
if grep -v "/$SHA_C/" "$REQUESTS" >/dev/null; then fail 'retry resolved a different revision'; fi

Pin_Script_Repo topic/fixture "$SHA_A"; Record_Install_Source
cp "$SCRIPT_FILES_SOURCE" "$TEST_DIR/completion-before"
cp "$SCRIPT_DIR/vpnmgr_www.js" "$TEST_DIR/js-before"
FIXTURE_FAIL=vpnmgr_www.js
if Sync_Addon_Files; then fail 'failed JavaScript download accepted'; fi
cmp -s "$TEST_DIR/completion-before" "$SCRIPT_FILES_SOURCE" || fail 'JavaScript failure marked complete'
cmp -s "$TEST_DIR/js-before" "$SCRIPT_DIR/vpnmgr_www.js" || fail 'failed JavaScript download replaced saved file'
cmp -s "$TEST_DIR/js-before" "$SCRIPT_WEB_DIR/vpnmgr_www.js" || fail 'failed JavaScript download replaced served file'
FIXTURE_FAIL=""; Sync_Addon_Files
printf 'stale served file\n' > "$SCRIPT_WEB_DIR/vpnmgr_www.js"
Update_File vpnmgr_www.js
cmp -s "$SCRIPT_DIR/vpnmgr_www.js" "$SCRIPT_WEB_DIR/vpnmgr_www.js" || fail 'unchanged saved JavaScript did not repair served copy'

# Exact-source test routing fails closed, including a valid-looking failed curl.
SCRIPT_BRANCH_OVERRIDE=topic/fixture
FIXTURE_API_FAIL=true; : > "$REQUESTS"
if Update_Version force unattended; then fail 'failed pin allowed update'; fi
eq 'failed pin had only one lookup' 1 "$(wc -l < "$REQUESTS" | tr -d ' ')"
FIXTURE_API_FAIL=false
FIXTURE_FAIL=vpnmgr.sh; : > "$REQUESTS"
if Update_Version force unattended; then fail 'failed main script probe allowed update'; fi
if grep -Eq '/(www/|providers/|vpnmgr_www\.)' "$REQUESTS"; then fail 'main probe failure still changed assets'; fi
FIXTURE_FAIL=""
if Pin_Script_Repo main invalid; then fail 'malformed supplied SHA accepted'; fi
SCRIPT_BRANCH_OVERRIDE=""; VPNMGR_INSTALL_SHA=invalid; : > "$REQUESTS"
if Resolve_Installed_Source; then fail 'invalid explicit installed SHA adopted'; fi
none 'invalid explicit installed SHA'
SCRIPT_BRANCH_OVERRIDE=topic/fixture
unset VPNMGR_INSTALL_SHA
: > "$REQUESTS"
Select_Install_Source || fail 'normal direct install could not select its source'
eq 'direct install resolves once' 1 "$(grep -c '^https://api.github.com/' "$REQUESTS")"

# The branch override applies to every command, including develop/stable.
Pin_Script_Repo main "$SHA_A"
eq 'test branch remains selected' topic/fixture "$SCRIPT_BRANCH"
eq 'pinned test source' "https://raw.githubusercontent.com/fixture-owner/vpnmgr/$SHA_A" "$SCRIPT_REPO"

# Explicit developer opt-in is independent of source routing and status labels.
SCRIPT_BRANCH_OVERRIDE=""
VPNMGR_TEST_PROVIDERS=""; Configure_Test_Providers; unset VPNMGR_TEST_PROVIDERS
if Provider_WebUI_Enabled nordvpn UNTESTED; then fail 'untested provider enabled by default'; fi
VPNMGR_TEST_PROVIDERS=nordvpn; Configure_Test_Providers
Provider_WebUI_Enabled nordvpn UNTESTED || fail 'explicit test provider unavailable'
if Provider_WebUI_Enabled surfshark UNTESTED; then fail 'test opt-in exposed another provider'; fi
if Provider_WebUI_Enabled nordvpn TEMPLATE; then fail 'test opt-in exposed a template'; fi
Provider_WebUI_Enabled surfshark ACTIVE || fail 'active provider hidden'
VPNMGR_TEST_PROVIDERS=""; Configure_Test_Providers; unset VPNMGR_TEST_PROVIDERS
if Provider_WebUI_Enabled nordvpn UNTESTED; then fail 'test opt-in could not be removed'; fi
SCRIPT_BRANCH_OVERRIDE=topic/fixture
Configure_Test_Providers
Provider_WebUI_Enabled nordvpn UNTESTED || fail 'normal pinned test install hid NordVPN'

# Exercise actual forced-update calls, including environment passed through exec.
VPNMGR_TEST_REEXEC_FILE="$TEST_DIR/reexec"; VPNMGR_TEST_FUNCTIONS="$TEST_DIR/functions"
export VPNMGR_TEST_REEXEC_FILE VPNMGR_TEST_FUNCTIONS SCRIPT_REPOSITORY SCRIPT_BRANCH SCRIPT_BRANCH_OVERRIDE SCRIPT_SOURCE_REVISION_FILE ERR WARN
VPNMGR_INSTALL_SHA="$SHA_A"; export VPNMGR_INSTALL_SHA
FIXTURE_SHA="$SHA_B"; : > "$REQUESTS"
( Update_Version force unattended )
eq 'reexec uses fresh candidate, not inherited old SHA' "$SHA_B|topic/fixture|$SHA_B" "$(cat "$VPNMGR_TEST_REEXEC_FILE")"
eq 'one lookup per update' 1 "$(grep -c '^https://api.github.com/' "$REQUESTS")"
if grep '^https://raw.githubusercontent.com/' "$REQUESTS" | grep -v "/$SHA_B/" >/dev/null; then fail 'update mixed revisions'; fi
FIXTURE_SHA="$SHA_C"; : > "$REQUESTS"
( Update_Version force unattended )
eq 'next update resolves a newer candidate' "$SHA_C|topic/fixture|$SHA_C" "$(cat "$VPNMGR_TEST_REEXEC_FILE")"
# Same script bytes and version at a new SHA must still update all assets.
FIXTURE_SHA="$SHA_A"; Pin_Script_Repo topic/fixture "$SHA_C"; : > "$REQUESTS"
[ "$(Update_Check)" = 'false,v1.0.0,v1.0.0' ] || fail 'installed source baseline'
printf '%s|%s|%s\n' "$SCRIPT_REPOSITORY" "$SCRIPT_BRANCH" "$SHA_A" > "$SCRIPT_FILES_SOURCE"
eq 'incomplete assets trigger source repair' 'source,v1.0.0,v1.0.0' "$(Update_Check)"
Script_Source_Identity > "$SCRIPT_FILES_SOURCE"
: > "$REQUESTS"
printf 'y\n' | ( Update_Version "" )
eq 'normal update resolves new source in reexec' "$SHA_A|topic/fixture|$SHA_A" "$(cat "$VPNMGR_TEST_REEXEC_FILE")"
eq 'one lookup in normal update' 1 "$(grep -c '^https://api.github.com/' "$REQUESTS")"
if grep '^https://raw.githubusercontent.com/' "$REQUESTS" | grep -v "/$SHA_A/" >/dev/null; then fail 'normal update mixed revisions'; fi
grep -q '/vpnmgr_www.js$' "$REQUESTS" || fail 'asset-only update skipped assets'
unset VPNMGR_INSTALL_SHA VPNMGR_TEST_REEXEC_FILE VPNMGR_TEST_FUNCTIONS

Pin_Script_Repo topic/fixture "$SHA_C"
eq 'source-only update detected' 'source,v1.0.0,v1.0.0' "$(Update_Check)"
rm -f "$SCRIPT_SOURCE_REVISION_FILE"
eq 'missing provenance triggers update' 'source,v1.0.0,v1.0.0' "$(Update_Check)"

# Ordinary non-test routing retains its historical explicit branch fallback.
SCRIPT_BRANCH_OVERRIDE=""; FIXTURE_API_FAIL=true
Pin_Script_Repo develop
eq 'ordinary fallback' 'https://raw.githubusercontent.com/fixture-owner/vpnmgr/develop' "$SCRIPT_REPO"
eq 'ordinary fallback label' develop@unknown "$SCRIPT_SOURCE"
FIXTURE_API_FAIL=false

for entry in install setversion postupdate; do
	_entry_block="$(sed -n "/^[[:space:]]*${entry})/,/^[[:space:]]*;;/p" "$ROOT/vpnmgr.sh")"
	case "$entry" in install) _expected=Select_Install_Source ;; *) _expected=Resolve_Installed_Source ;; esac
	printf '%s\n' "$_entry_block" | grep -q "$_expected" || fail "$entry lacks source-selection wiring"
done
# Run the production install dispatcher and Menu_Install against owned fixtures.
{ printf 'case "$1" in\n'; sed -n '/^[[:space:]]*install)/,/^[[:space:]]*;;/p' "$ROOT/vpnmgr.sh"; printf 'esac\n'; } > "$TEST_DIR/install-dispatch"
(
	SCRIPT_DIR="$TEST_DIR/fresh"; SCRIPT_WWW_DIR="$SCRIPT_DIR/www"; PROVIDERS_DIR="$SCRIPT_DIR/providers"
	SCRIPT_WEB_DIR="$TEST_DIR/fresh-web"; SCRIPT_WEBPAGE_DIR="$TEST_DIR/fresh-pages"
	OVPN_ARCHIVE_DIR="$SCRIPT_DIR/archive"; VPNMGR_RUNTIME_DIR="$TEST_DIR/fresh-runtime"
	SCRIPT_SOURCE_REVISION_FILE="$SCRIPT_DIR/.install_revision"; SCRIPT_SOURCE_FILE="$SCRIPT_DIR/.install_source"
	SCRIPT_FILES_SOURCE="$SCRIPT_DIR/.files_source"; SCRIPT_FILES_VERSION="$SCRIPT_DIR/.files_version"
	SCRIPT_TEST_PROVIDER_FILE="$SCRIPT_DIR/.test_providers"
	mkdir -p "$SCRIPT_WEB_DIR" "$SCRIPT_WEBPAGE_DIR"
	SCRIPT_BRANCH_OVERRIDE=""; Pin_Script_Repo main "$SHA_A"
	Select_Install_Source(){ :; }; Bootstrap_Install(){ :; }; Check_Lock(){ :; }; Clear_Lock(){ printf 'clear\n' >> "$TEST_DIR/lock-clears"; }
	ScriptHeader(){ :; }; sleep(){ :; }; Check_Requirements(){ :; }; Conf_Exists(){ :; }
	Auto_Cron(){ :; }; Auto_Startup(){ :; }; Auto_ServiceEvent(){ :; }; Shortcut_Script(){ :; }
	Refresh_Provider_Cache(){ :; }; MainMenu(){ :; }
	FIXTURE_FAIL=vpnmgr_www.js
	if ( set +e; set -- install; . "$TEST_DIR/install-dispatch" ); then fail 'failed fresh install returned success'; fi
	[ -f "$SCRIPT_DIR/providers_list" ] || fail 'failed install lacks owned marker'
	[ -s "$TEST_DIR/lock-clears" ] || fail 'failed install did not clear lock'
	FIXTURE_FAIL=""
	( set +e; set -- install; . "$TEST_DIR/install-dispatch" ) || fail 'failed fresh install cannot retry'
	[ -f "$SCRIPT_DIR/vpnmgr_www.js" ] || fail 'retry did not install JavaScript'
	cmp -s "$SCRIPT_DIR/vpnmgr_www.js" "$SCRIPT_WEB_DIR/vpnmgr_www.js" || fail 'retry did not publish JavaScript'
	# Existing legacy providers without the ownership marker are still rejected.
	SCRIPT_DIR="$TEST_DIR/legacy"; mkdir -p "$SCRIPT_DIR/providers"
	if ( set +e; set -- install; . "$TEST_DIR/install-dispatch" ); then fail 'legacy install incorrectly adopted'; fi
)
# A real final copy failure must propagate through both production reentry clauses.
(
	SCRIPT_DIR="$TEST_DIR/copy-fail"; SCRIPT_WEB_DIR="$TEST_DIR/copy-web"; PROVIDERS_DIR="$SCRIPT_DIR/providers"
	SCRIPT_WWW_DIR="$SCRIPT_DIR/www"; VPNMGR_RUNTIME_DIR="$TEST_DIR/copy-runtime"
	mkdir -p "$SCRIPT_DIR" "$SCRIPT_WEB_DIR" "$PROVIDERS_DIR"
	if Create_Symlinks; then fail 'missing source JS accepted by Create_Symlinks'; fi
	Resolve_Installed_Source(){ :; }; Set_Version_Custom_Settings(){ :; }; opkg(){ :; }
	Create_Dirs(){ :; }; Conf_Exists(){ :; }; Auto_Cron(){ :; }; Auto_Startup(){ :; }
	Auto_ServiceEvent(){ :; }; Shortcut_Script(){ :; }; Sync_Addon_Files(){ :; }; Refresh_Provider_Cache(){ :; }
	for entry in setversion postupdate; do
		{ printf 'case "$1" in\n'; sed -n "/^[[:space:]]*${entry})/,/^[[:space:]]*;;/p" "$ROOT/vpnmgr.sh"; printf 'esac\n'; } > "$TEST_DIR/reentry-dispatch"
		if ( set -- "$entry"; . "$TEST_DIR/reentry-dispatch" ); then fail "$entry masked served-copy failure"; fi
	done
	# Interactive update reexec uses the actual no-argument startup path.
	sed -n '/^if \[ -z "\$1" \]; then/,/^fi$/p' "$ROOT/vpnmgr.sh" > "$TEST_DIR/interactive-startup"
	NTP_Ready(){ :; }; Entware_Ready(){ :; }; ScriptHeader(){ :; }
	MainMenu(){ fail 'interactive startup reached menu after a source/copy failure'; }
	if ( set +u; set --; . "$TEST_DIR/interactive-startup" ); then fail 'interactive startup masked copy failure'; fi
	Sync_Addon_Files(){ return 1; }
	if ( set +u; set --; . "$TEST_DIR/interactive-startup" ); then fail 'interactive startup masked source failure'; fi
)
# Execute the actual WebUI dispatch branches, including unattended force arguments.
sed -n '/elif \[ "$2" = "start" \] && \[ "$3" = "${SCRIPT_NAME}checkupdate" \]/,/^[[:space:]]*fi$/p' "$ROOT/vpnmgr.sh" | sed '1s/elif /if /' > "$TEST_DIR/web-dispatch"
(
	Update_Check(){ return 37; }
	Update_Version(){ [ "$1" = force ] && [ "$2" = unattended ] || return 88; return 39; }
	if ( set -- service_event start vpnmgrcheckupdate; . "$TEST_DIR/web-dispatch" ); then fail 'checkupdate failure masked'; else _event_rc=$?; fi
	eq 'checkupdate status' 37 "$_event_rc"
	if ( set -- service_event start vpnmgrdoupdate; . "$TEST_DIR/web-dispatch" ); then fail 'doupdate failure masked'; else _event_rc=$?; fi
	eq 'doupdate status and unattended arguments' 39 "$_event_rc"
)
printf 'Source/bootstrap/download and test-provider checks passed (offline).\n'
