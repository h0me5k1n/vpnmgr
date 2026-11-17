#!/bin/sh
# Isolated production function tests; never source or execute the router manager.
# shellcheck disable=SC2034
set -eu
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
for fn in Runtime_Init Runtime_ValidID Runtime_Write Runtime_Detect Runtime_Status Runtime_Release Runtime_Recover Runtime_Prepare Runtime_Merge Runtime_Apply Runtime_Apply_Cleanup Parse_OpenVPN_Version Detect_OpenVPN_Runtime; do
	sed -n "/^${fn}(){/,/^}/p" "$ROOT/vpnmgr.sh"
done | sed "s|/usr/sbin/openvpn|$TEST_DIR/openvpn|g" > "$TEST_DIR/functions"
. "$TEST_DIR/functions"
VPNMGR_RUNTIME_DIR="$TEST_DIR/runtime"; VPNMGR_SETTINGS_FILE="$TEST_DIR/settings"; SCRIPT_CONF="$TEST_DIR/config"
export VPNMGR_RUNTIME_DIR VPNMGR_SETTINGS_FILE SCRIPT_CONF
# shellcheck disable=SC2034
WARN=; ERR=; PASS=; CRIT=; TEST_FAIL=0
Print_Output(){ :; }
nvram(){ case "$1" in set) printf '%s\n' "$2" >> "$TEST_DIR/nvram"; [ "$TEST_FAIL" != set ] ;; commit) [ "$TEST_FAIL" != commit ] ;; esac; }
ManageVPN(){ :; }
UnmanageVPN(){ :; }
ScheduleVPN(){ :; }
CancelScheduleVPN(){ :; }
# shellcheck disable=SC2034
UpdateVPNConfig(){ printf '%s\n' "$2" >> "$TEST_DIR/calls"; VPNMGR_UPDATE_CONNECTION=not_requested; [ "$2" != 2 ]; }
fail(){ printf 'FAIL: %s\n' "$1" >&2; exit 1; }
contains(){ grep -Fq "$2" "$1" || fail "$3"; }
printf '#!/bin/sh\nprintf "OpenVPN 2.6.9 vendor\\n"\n' > "$TEST_DIR/openvpn"; chmod +x "$TEST_DIR/openvpn"
Runtime_Detect 8
contains "$VPNMGR_RUNTIME_DIR/detection_8.json" '"family":"modern","status":"detected"' 'known runtime'
printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/openvpn"
Runtime_Detect 9
contains "$VPNMGR_RUNTIME_DIR/detection_9.json" '"family":"legacy","status":"unknown"' 'unknown runtime'
if Runtime_Detect bad; then fail 'invalid nonce accepted'; fi
if Runtime_ValidID 123456789012345678901234567890123; then fail 'long nonce accepted'; fi
Runtime_Prepare 1; Runtime_Prepare 2
contains "$VPNMGR_RUNTIME_DIR/apply_1.json" '"state":"ready"' 'reservation ready'
contains "$VPNMGR_RUNTIME_DIR/apply_2.json" '"state":"busy"' 'second reservation busy'
printf '0\n' > "$VPNMGR_RUNTIME_DIR/apply.lock/ready.1"
Runtime_Prepare 3
contains "$VPNMGR_RUNTIME_DIR/apply_1.json" '"message":"expired"' 'expired ready'
contains "$VPNMGR_RUNTIME_DIR/apply_3.json" '"state":"ready"' 'replacement ready'
cat > "$SCRIPT_CONF" <<'DATA'
vpn1_managed=false
vpn1_location=old
vpn1_schenabled=false
vpn2_managed=false
vpn2_schenabled=false
vpn3_managed=false
vpn3_schenabled=false
vpn4_managed=false
vpn4_schenabled=false
vpn5_managed=false
vpn5_schenabled=false
DATA
cat > "$VPNMGR_SETTINGS_FILE" <<'DATA'
otheraddon_value preserve me
vpnmgr_version_local 1
vpnmgr_request_id 99
vpnmgr_vpn1_location foreign data
DATA
Runtime_Apply 3
contains "$VPNMGR_RUNTIME_DIR/apply_3.json" '"state":"superseded"' 'wrong nonce'
contains "$VPNMGR_SETTINGS_FILE" 'vpnmgr_request_id 99' 'foreign submission preserved'
contains "$SCRIPT_CONF" 'vpn1_location=old' 'no foreign merge'
[ ! -d "$VPNMGR_RUNTIME_DIR/apply.lock" ] || fail 'lock released'
Runtime_Prepare 4
cat > "$VPNMGR_SETTINGS_FILE" <<'DATA'
otheraddon_value preserve me
vpnmgr_version_local 1
vpnmgr_request_id 4
vpnmgr_vpn1_managed true
vpnmgr_vpn1_location New York = East
vpnmgr_vpn1_usn user name=ok
vpnmgr_vpn1_pwd secret=pass word
vpnmgr_vpn2_managed true
DATA
Runtime_Apply 4
contains "$SCRIPT_CONF" 'vpn1_location=New York = East' 'location preserved'
contains "$TEST_DIR/nvram" 'vpn_client1_password=secret=pass word' 'credential preserved'
contains "$VPNMGR_SETTINGS_FILE" 'otheraddon_value preserve me' 'unrelated settings preserved'
contains "$VPNMGR_SETTINGS_FILE" 'vpnmgr_version_local 1' 'version preserved'
contains "$VPNMGR_RUNTIME_DIR/apply_4.json" '"slot":1,"status":"applied","connection":"not_requested"' 'first client applied'
contains "$VPNMGR_RUNTIME_DIR/apply_4.json" '"slot":2,"status":"failed"' 'second client failed'
contains "$VPNMGR_RUNTIME_DIR/apply_4.json" '"slot":5,"status":"unmanaged"' 'remaining slots processed'
if grep -Fq 'secret=pass' "$VPNMGR_RUNTIME_DIR/apply_4.json"; then fail 'credential in status'; fi
Runtime_Apply 4 || :
[ "$(wc -l < "$TEST_DIR/calls" | tr -d ' ')" = 2 ] || fail 'duplicate event reapplied'
Runtime_Prepare 5
printf 'vpnmgr_request_id 5\nvpnmgr_vpn1_location failed\n' > "$VPNMGR_SETTINGS_FILE"
TEST_FAIL=commit
Runtime_Apply 5
contains "$VPNMGR_RUNTIME_DIR/apply_5.json" '"state":"failed"' 'merge failure'
[ ! -d "$VPNMGR_RUNTIME_DIR/apply.lock" ] || fail 'failure lock released'
contains "$VPNMGR_SETTINGS_FILE" 'vpnmgr_request_id 5' 'failed submission retained'
# A failed initial publication must prevent both the merge and client updates.
TEST_FAIL=0
Runtime_Prepare 6
printf 'vpnmgr_request_id 6\nvpnmgr_vpn1_location must-not-merge\n' > "$VPNMGR_SETTINGS_FILE"
cp "$SCRIPT_CONF" "$TEST_DIR/before-publish"
(
	Runtime_Write(){ return 1; }
	if Runtime_Apply 6; then fail 'failed publisher reported success'; fi
)
cmp "$SCRIPT_CONF" "$TEST_DIR/before-publish" || fail 'failed initial status allowed merge'
[ ! -d "$VPNMGR_RUNTIME_DIR/apply.lock" ] || fail 'publisher failure retained lock'
# Exit from the merge simulates interruption while a credential snapshot exists.
Runtime_Prepare 7
printf 'vpnmgr_request_id 7\nvpnmgr_vpn1_pwd sensitive-secret\n' > "$VPNMGR_SETTINGS_FILE"
(
	Runtime_Merge(){ [ -f "$1" ] || fail 'snapshot missing before abort'; exit 73; }
	if Runtime_Apply 7; then fail 'interrupted apply reported success'; fi
)
contains "$VPNMGR_RUNTIME_DIR/apply_7.json" '"message":"interrupted"' 'interruption status'
[ ! -d "$VPNMGR_RUNTIME_DIR/apply.lock" ] || fail 'interruption retained lock'
[ -z "$(ls -A "$VPNMGR_RUNTIME_DIR-private")" ] || fail 'private files retained'
[ ! -e "$VPNMGR_RUNTIME_DIR/private" ] || fail 'private directory is web-served'
if grep -r -q 'sensitive-secret' "$VPNMGR_RUNTIME_DIR" 2>/dev/null; then fail 'credential under served runtime'; fi
# Fail one progress publication after merging, then allow the failure status.
sed -n '/^Runtime_Write(){/,/^}/p' "$ROOT/vpnmgr.sh" | sed '1s/Runtime_Write/Runtime_Write_Real/' > "$TEST_DIR/write-real"
. "$TEST_DIR/write-real"
Runtime_Prepare 10
printf 'vpnmgr_request_id 10\nvpnmgr_vpn1_managed true\n' > "$VPNMGR_SETTINGS_FILE"
cp "$TEST_DIR/calls" "$TEST_DIR/calls-before"
(
	Runtime_Write(){
		case "$2" in *'"status":"applying"'*)
			if [ ! -f "$TEST_DIR/publish-failed" ]; then touch "$TEST_DIR/publish-failed"; return 1; fi ;;
		esac
		Runtime_Write_Real "$@"
	}
	if Runtime_Apply 10; then fail 'failed progress publisher reported success'; fi
)
cmp "$TEST_DIR/calls" "$TEST_DIR/calls-before" || fail 'updates continued after progress publication failure'
contains "$VPNMGR_RUNTIME_DIR/apply_10.json" '"state":"failed","merged":true' 'partial merge status'
contains "$VPNMGR_RUNTIME_DIR/apply_10.json" '"message":"status_failed"' 'progress failure status'
[ ! -d "$VPNMGR_RUNTIME_DIR/apply.lock" ] || fail 'progress failure retained lock'
Runtime_Prepare 11
printf 'vpnmgr_request_id 11\nvpnmgr_vpn1_managed true\n' > "$VPNMGR_SETTINGS_FILE"
(
	Runtime_Write(){
		case "$2" in *'"state":"done"'*) return 1 ;; esac
		Runtime_Write_Real "$@"
	}
	if Runtime_Apply 11; then fail 'failed final publisher reported success'; fi
)
contains "$VPNMGR_RUNTIME_DIR/apply_11.json" '"message":"status_failed"' 'final failure status'
[ ! -d "$VPNMGR_RUNTIME_DIR/apply.lock" ] || fail 'final failure retained lock'
# Recover a lost settings POST without submitting or merging it a second time.
Runtime_Prepare 20
Runtime_Recover 20
[ -f "$VPNMGR_RUNTIME_DIR/apply.lock/ready.20" ] || fail 'young reservation expired'
Runtime_Recover 999
[ -f "$VPNMGR_RUNTIME_DIR/apply.lock/ready.20" ] || fail 'wrong request changed reservation'
printf '0\n' > "$VPNMGR_RUNTIME_DIR/apply.lock/ready.20"
(
	Runtime_Write(){ return 1; }
	if Runtime_Recover 20; then fail 'failed expiry publication accepted'; fi
)
[ -f "$VPNMGR_RUNTIME_DIR/apply.lock/ready.20" ] || fail 'publication failure stranded recovery'
Runtime_Recover 20
contains "$VPNMGR_RUNTIME_DIR/apply_20.json" '"message":"expired"' 'lost POST expiry'
[ ! -d "$VPNMGR_RUNTIME_DIR/apply.lock" ] || fail 'expired reservation not released'
cp "$SCRIPT_CONF" "$TEST_DIR/before-late"
printf 'vpnmgr_request_id 20\nvpnmgr_vpn1_location late-must-not-merge\n' > "$VPNMGR_SETTINGS_FILE"
if Runtime_Apply 20; then fail 'late expired apply accepted'; fi
cmp -s "$SCRIPT_CONF" "$TEST_DIR/before-late" || fail 'late expired payload merged'
Runtime_Prepare 21
printf 'vpnmgr_request_id 21\nvpnmgr_vpn1_managed true\n' > "$VPNMGR_SETTINGS_FILE"
(
	ManageVPN(){
		Runtime_Recover 21
		contains "$VPNMGR_RUNTIME_DIR/apply_21.json" '"state":"running"' 'running apply was expired'
	}
	Runtime_Apply 21
)
contains "$VPNMGR_RUNTIME_DIR/apply_21.json" '"state":"done"' 'late delivered apply completion'
cp "$VPNMGR_RUNTIME_DIR/apply_21.json" "$TEST_DIR/completed"
Runtime_Recover 21
cmp -s "$VPNMGR_RUNTIME_DIR/apply_21.json" "$TEST_DIR/completed" || fail 'completed result changed'
# Pause an old process at its claim while expiry/release + another Prepare occur.
# The old process must not consume the newer request's ready token (ABA race).
for old in 80 82; do
	new=$((old + 1)); Runtime_Prepare "$old"
	printf '0\n' > "$VPNMGR_RUNTIME_DIR/apply.lock/ready.$old"
	(
		# Match the production manager's shell flags during the injected race;
		# every observed outcome is checked explicitly below.
		set +e
		mv(){
			if [ "$1" = "$VPNMGR_RUNTIME_DIR/apply.lock/ready.$old" ]; then
				rm -f "$VPNMGR_RUNTIME_DIR/apply.lock/ready.$old" "$VPNMGR_RUNTIME_DIR/apply.lock/owner"
				rmdir "$VPNMGR_RUNTIME_DIR/apply.lock"
				(Runtime_Prepare "$new") || fail 'intervening prepare failed'
				touch "$TEST_DIR/raced.$old"
			fi
			command mv "$@"
		}
		if [ "$old" = 80 ]; then Runtime_Recover "$old" || fail 'old recovery claim failed'; else Runtime_Apply "$old" || fail 'old apply claim failed'; fi
	)
	[ -f "$TEST_DIR/raced.$old" ] || fail 'claim race not exercised'
	[ "$(cat "$VPNMGR_RUNTIME_DIR/apply.lock/owner")" = "$new" ] || fail 'old process released newer owner'
	[ -f "$VPNMGR_RUNTIME_DIR/apply.lock/ready.$new" ] || fail 'old process consumed newer ready token'
	printf '0\n' > "$VPNMGR_RUNTIME_DIR/apply.lock/ready.$new"
	Runtime_Recover "$new"
done
grep -Fq '"${SCRIPT_NAME}runtime_"*)' "$ROOT/vpnmgr.sh" || fail 'runtime dispatch'
grep -Fq '[ "$3" = "$SCRIPT_NAME" ]' "$ROOT/vpnmgr.sh" || fail 'legacy dispatch'
# Exercise the actual restart boundary with inert processes and services.
sed -n '/^RestartVPNClient(){/,/^}/p' "$ROOT/vpnmgr.sh" | sed "s|/opt/bin/xargs|\"$TEST_DIR/xargs\"|g" > "$TEST_DIR/restart"
. "$TEST_DIR/restart"
touch "$TEST_DIR/xargs"
sleep(){ :; }
ps(){ :; }
xargs(){ :; }
service(){ [ "$SERVICE_FAIL" != "$1" ]; }
SERVICE_FAIL=stop_vpnclient1
if RestartVPNClient 1; then fail 'restart stop failure masked'; fi
SERVICE_FAIL=start_vpnclient1
if RestartVPNClient 1; then fail 'restart start failure masked'; fi
SERVICE_FAIL=none
RestartVPNClient 1 || fail 'restart success'
# Exercise real update return paths with a minimal provider and no waits/network.
for fn in Default_VPN_Data_Ciphers Normalize_OVPN_Profile UpdateVPNConfig; do
	sed -n "/^${fn}(){/,/^}/p" "$ROOT/vpnmgr.sh"
done > "$TEST_DIR/update"
(
	. "$TEST_DIR/update"
	cat > "$SCRIPT_CONF" <<'DATA'
vpn1_provider=Fixture
vpn1_protocol=UDP
vpn1_type=Standard
vpn1_countryid=1
vpn1_countryname=Country
vpn1_cityid=2
vpn1_cityname=City
vpn1_customsettings=true
DATA
	Detect_OpenVPN_Runtime(){ OVPN_RUNTIME_FAMILY=legacy; OVPN_RUNTIME_NUMBER=2005000; }
	Load_Provider(){ :; }
	provider_fixture_get_server(){ printf server; }
	provider_fixture_get_ovpn(){ printf profile; }
	provider_fixture_get_hmac(){ printf 1; }
	provider_fixture_get_short_name(){ printf short; }
	provider_fixture_get_desc(){ printf desc; }
	provider_fixture_get_comp(){ printf no; }
	provider_fixture_write_certs(){ :; }
	getIP(){ printf 1.2.3.4; }
	getPort(){ printf 1194; }
	getCipher(){ printf AES-256-CBC; }
	getAuthDigest(){ printf SHA256; }
	getClientCA(){ printf ca; }
	getConnectState(){ printf 0; }
	Firmware_Build_Before(){ return 1; }
	SetVPNCustomSettings(){ :; }
	RestartVPNClient(){ [ "$RESTART_FAIL" = no ]; }
	nvram(){
		case "$1:${2:-}" in
			get:vpn_clientx_eas) [ "$AUTO_CONNECT" = yes ] && printf 1; return 0 ;;
			get:vpn_client1_addr) printf old; return 0 ;;
			get:*) return 0 ;;
			set:*) [ "$WRITE_FAIL" = no ]; return $? ;;
			commit:*) return 0 ;;
		esac
	}
	AUTO_CONNECT=no; WRITE_FAIL=yes; RESTART_FAIL=no
	if UpdateVPNConfig unattended 1 0; then fail 'nvram write failure masked'; fi
	AUTO_CONNECT=yes; WRITE_FAIL=no; RESTART_FAIL=yes
	if UpdateVPNConfig unattended 1 0; then fail 'update restart failure masked'; fi
	RESTART_FAIL=no
	if UpdateVPNConfig unattended 1 0; then fail 'exhausted connection returned success'; fi
	[ "$VPNMGR_UPDATE_CONNECTION" = failed ] || fail 'connection failure status'
	AUTO_CONNECT=no
	UpdateVPNConfig unattended 1 0 || fail 'update without auto-connect'
	[ "$VPNMGR_UPDATE_CONNECTION" = not_requested ] || fail 'not-requested connection status'
	# A successful verification must report the final restored state accurately.
	AUTO_CONNECT=yes; TEST_CONNECTION_STATE=0; TEST_STOP_COUNT=0; STOP_FAIL=no
	getConnectState(){ printf '%s' "$TEST_CONNECTION_STATE"; }
	RestartVPNClient(){ TEST_CONNECTION_STATE=2; }
	service(){
		[ "$1" = stop_vpnclient1 ] || return 1
		TEST_STOP_COUNT=$((TEST_STOP_COUNT + 1))
		[ "$STOP_FAIL" = no ] || return 1
		TEST_CONNECTION_STATE=0
	}
	UpdateVPNConfig unattended 1 0 || fail 'stopped client verification failed'
	[ "$TEST_CONNECTION_STATE:$VPNMGR_UPDATE_CONNECTION" = 0:verified_stopped ] || fail 'stopped client falsely reported connected'
	[ "$TEST_STOP_COUNT" = 1 ] || fail 'prior stopped state not restored'
	TEST_STOP_COUNT=0
	UpdateVPNConfig unattended 1 2 || fail 'prior connected client update failed'
	[ "$TEST_CONNECTION_STATE:$VPNMGR_UPDATE_CONNECTION:$TEST_STOP_COUNT" = 2:connected:0 ] || fail 'prior connected client was stopped'
	STOP_FAIL=yes
	if UpdateVPNConfig unattended 1 0; then fail 'failed state restoration accepted'; fi
	[ "$VPNMGR_UPDATE_CONNECTION" = unknown ] || fail 'failed stop still reported connected'
)
printf 'WebUI backend request, merge, and update checks passed.\n'  
