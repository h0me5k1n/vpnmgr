#!/bin/sh

#######################################################
##                                                   ##
##   __   __ _ __   _ __   _ __ ___    __ _  _ __    ##
##   \ \ / /| '_ \ | '_ \ | '_ ` _ \  / _` || '__|   ##
##    \ V / | |_) || | | || | | | | || (_| || |      ##
##     \_/  | .__/ |_| |_||_| |_| |_| \__, ||_|      ##
##          | |                        __/ |         ##
##          |_|                       |___/          ##
##                                                   ##
##       https://github.com/h0me5k1n/vpnmgr          ##
##     Originally by h0me5k1n, expanded by jackyaz   ##
##     Revived and maintained by h0me5k1n            ##
#######################################################

##########         Shellcheck directives     ##########
# shellcheck disable=SC1090
# shellcheck disable=SC2009
# shellcheck disable=SC2317
# shellcheck disable=SC2016
# shellcheck disable=SC2018
# shellcheck disable=SC2019
# shellcheck disable=SC2039
# shellcheck disable=SC2059
# shellcheck disable=SC2140
# shellcheck disable=SC2155
# shellcheck disable=SC3003
#######################################################

### Start of script variables ###
readonly SCRIPT_NAME="vpnmgr"
readonly SCRIPT_VERSION="v3.4.1"
SCRIPT_BRANCH="main"
SCRIPT_REPOSITORY="h0me5k1n/vpnmgr"
SCRIPT_BRANCH_OVERRIDE=""
SCRIPT_REPO="https://raw.githubusercontent.com/$SCRIPT_REPOSITORY/$SCRIPT_BRANCH"
SCRIPT_REVISION=""
SCRIPT_UPDATE_READY="false"
readonly SCRIPT_DIR="/jffs/addons/$SCRIPT_NAME.d"
readonly SCRIPT_CONF="$SCRIPT_DIR/config"
readonly OVPN_ARCHIVE_DIR="$SCRIPT_DIR/ovpn"
readonly PROVIDERS_DIR="$SCRIPT_DIR/providers"
readonly SCRIPT_WEBPAGE_DIR="$(readlink /www/user)"
readonly SCRIPT_WEB_DIR="$SCRIPT_WEBPAGE_DIR/$SCRIPT_NAME"
readonly SCRIPT_WWW_DIR="$SCRIPT_DIR/www"
readonly SCRIPT_FILES_VERSION="$SCRIPT_DIR/.files_version"
readonly SCRIPT_SOURCE_FILE="$SCRIPT_DIR/.install_source"
readonly SCRIPT_SOURCE_REVISION_FILE="$SCRIPT_DIR/.install_revision"
readonly SCRIPT_FILES_SOURCE="$SCRIPT_DIR/.files_source"
readonly SCRIPT_TEST_PROVIDER_FILE="$SCRIPT_DIR/.test_providers"
SCRIPT_SOURCE=""
[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
GLOBAL_VPN_NO=""
GLOBAL_VPN_PROVIDER=""
GLOBAL_VPN_PROT=""
GLOBAL_VPN_TYPE=""
GLOBAL_CRU_DAYNUMBERS=""
GLOBAL_CRU_HOURS=""
GLOBAL_CRU_MINS=""
GLOBAL_COUNTRY_NAME=""
GLOBAL_COUNTRY_ID=""
GLOBAL_CITY_NAME=""
GLOBAL_CTIY_ID=""
### End of script variables ###

### Start of output format variables ###
readonly CRIT="\\e[41m"
readonly ERR="\\e[31m"
readonly WARN="\\e[33m"
readonly PASS="\\e[32m"
readonly BOLD="\\e[1m"
readonly SETTING="${BOLD}\\e[36m"
readonly CLEARFORMAT="\\e[0m"
### End of output format variables ###

# $1 = print to syslog, $2 = message to print, $3 = log level
Print_Output(){
	if [ "$1" = "true" ]; then
		logger -t "$SCRIPT_NAME" "$2"
	fi
	printf "${BOLD}${3}%s${CLEARFORMAT}\\n\\n" "$2"
}

Load_Provider(){
	_lp_provider="$1"
	_lp_script="${PROVIDERS_DIR}/provider_${_lp_provider}.sh"
	if [ -f "$_lp_script" ]; then
		. "$_lp_script"
		return 0
	else
		Print_Output true "Provider module not found: $_lp_provider (run vpnmgr update)" "$ERR"
		return 1
	fi
}

Firmware_Version_Check(){
	if nvram get rc_support | grep -qF "am_addons"; then
		return 0
	else
		return 1
	fi
}

Firmware_Number_Check(){
	echo "$1" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
}

Firmware_Build_Before(){
	# Legacy thresholds refer to the 3.0.0.4 family. Newer families restarted
	# build numbering (3.0.0.6 uses 102.x); absent/unknown families keep the
	# previous build-only comparison for compatibility.
	_fbb_family="$(nvram get firmver)"
	if printf '%s\n' "$_fbb_family" | grep -Eq '^[0-9]+(\.[0-9]+){3}$' &&
		[ "$(Firmware_Number_Check "$_fbb_family")" -gt "$(Firmware_Number_Check 3.0.0.4)" ]; then
		return 1
	fi
	[ "$(Firmware_Number_Check "$(nvram get buildno)")" -lt "$(Firmware_Number_Check "$1")" ]
}

Parse_OpenVPN_Version(){
	# A missing patch is zero; vendor/prerelease suffixes do not affect the
	# numeric family. Reject malformed tokens instead of coercing them to zero.
	printf '%s\n' "$1" | awk 'NR==1 {
		if ($1 != "OpenVPN" || $2 !~ /^[0-9]+\.[0-9]+(\.[0-9]+)?([-+_][[:alnum:]][[:alnum:].+_-]*)?$/) exit 1;
		split($2,core,/[-+_]/); n=split(core[1],v,".");
		if (v[1]<2 || v[1]>99 || v[2]>999 || (n==3 && v[3]>999)) exit 1;
		printf "%s|%d%03d%03d|%s\n", $2,v[1],v[2],(n==3?v[3]:0),
			(v[1]>2 || (v[1]==2 && v[2]>=6) ? "modern" : "legacy");
		exit;
	}'
}

Detect_OpenVPN_Runtime(){
	OVPN_RUNTIME_VERSION=""
	OVPN_RUNTIME_NUMBER=""
	OVPN_RUNTIME_FAMILY="legacy"
	OVPN_RUNTIME_STATUS="unknown"
	# Merlin starts this executable, independently of Entware's PATH and of
	# whether any VPN client is currently running. Keep its exit status.
	if [ -x "/usr/sbin/openvpn" ] &&
		_ovr_banner="$("/usr/sbin/openvpn" --version 2>/dev/null)" &&
		_ovr_info="$(Parse_OpenVPN_Version "$_ovr_banner")" && [ -n "$_ovr_info" ]; then
		OVPN_RUNTIME_VERSION="${_ovr_info%%|*}"
		_ovr_info="${_ovr_info#*|}"
		OVPN_RUNTIME_NUMBER="${_ovr_info%%|*}"
		OVPN_RUNTIME_FAMILY="${_ovr_info#*|}"
		OVPN_RUNTIME_STATUS="detected"
	else
		Print_Output true "Built-in OpenVPN version is unavailable or invalid; using legacy profiles and settings" "$WARN" >&2
	fi
	return 0
}

OpenVPN_Version_Number(){
	Detect_OpenVPN_Runtime
	[ -n "$OVPN_RUNTIME_NUMBER" ] && printf '%s\n' "$OVPN_RUNTIME_NUMBER"
}

### Code for these functions inspired by https://github.com/Adamm00 - credit to @Adamm ###
Check_Lock(){
	if [ -f "/tmp/$SCRIPT_NAME.lock" ]; then
		ageoflock=$(($(date +%s) - $(date +%s -r /tmp/$SCRIPT_NAME.lock)))
		if [ "$ageoflock" -gt 600 ]; then
			Print_Output true "Stale lock file found (>600 seconds old) - purging lock" "$ERR"
			kill "$(sed -n '1p' /tmp/$SCRIPT_NAME.lock)" >/dev/null 2>&1
			Clear_Lock
			echo "$$" > "/tmp/$SCRIPT_NAME.lock"
			return 0
		else
			Print_Output true "Lock file found (age: $ageoflock seconds) - stopping to prevent duplicate runs" "$ERR"
			if [ -z "$1" ]; then
				exit 1
			else
				if [ "$1" = "webui" ]; then
					echo 'var vpnmgrstatus = "LOCKED";' > /tmp/detect_vpnmgr.js
					exit 1
				fi
				return 1
			fi
		fi
	else
		echo "$$" > "/tmp/$SCRIPT_NAME.lock"
		trap 'Trap_Exit' INT TERM
		return 0
	fi
}

Clear_Lock(){
	rm -f "/tmp/$SCRIPT_NAME.lock" 2>/dev/null
	return 0
}

Trap_Exit(){
	# Restore the terminal if interrupted while the picker has it in raw mode
	[ -n "$PICK_STTY" ] && stty "$PICK_STTY" 2>/dev/null && printf '\r\033[J'
	Clear_Lock
	exit 1
}

###################################

Set_Version_Custom_Settings(){
	SETTINGSFILE="/jffs/addons/custom_settings.txt"
	case "$1" in
		local)
			if [ -f "$SETTINGSFILE" ]; then
				if [ "$(grep -c "vpnmgr_version_local" $SETTINGSFILE)" -gt 0 ]; then
					if [ "$2" != "$(grep "vpnmgr_version_local" /jffs/addons/custom_settings.txt | cut -f2 -d' ')" ]; then
						sed -i "s/vpnmgr_version_local.*/vpnmgr_version_local $2/" "$SETTINGSFILE"
					fi
				else
					echo "vpnmgr_version_local $2" >> "$SETTINGSFILE"
				fi
			else
				echo "vpnmgr_version_local $2" >> "$SETTINGSFILE"
			fi
		;;
		source)
			# Shown beside the version in the WebUI. The key must contain
			# "version" so Conf_FromSettings keeps it rather than merging it.
			if [ -f "$SETTINGSFILE" ]; then
				sed -i '/^vpnmgr_version_source /d' "$SETTINGSFILE"
			fi
			if [ -n "$2" ]; then
				echo "vpnmgr_version_source $2" >> "$SETTINGSFILE"
			fi
		;;
		server)
			if [ -f "$SETTINGSFILE" ]; then
				if [ "$(grep -c "vpnmgr_version_server" $SETTINGSFILE)" -gt 0 ]; then
					if [ "$2" != "$(grep "vpnmgr_version_server" /jffs/addons/custom_settings.txt | cut -f2 -d' ')" ]; then
						sed -i "s/vpnmgr_version_server.*/vpnmgr_version_server $2/" "$SETTINGSFILE"
					fi
				else
					echo "vpnmgr_version_server $2" >> "$SETTINGSFILE"
				fi
			else
				echo "vpnmgr_version_server $2" >> "$SETTINGSFILE"
			fi
		;;
	esac
}

# Pin_Script_Repo branch
# Points SCRIPT_REPO at the commit the branch currently resolves to, so every
# file in the install comes from that one commit even if the branch moves
# meanwhile, and sets SCRIPT_SOURCE to "<branch>@<short commit>".
Unpinned_Script_Repo(){
	SCRIPT_BRANCH="$1"; SCRIPT_REVISION=""
	SCRIPT_REPO="https://raw.githubusercontent.com/$SCRIPT_REPOSITORY/$SCRIPT_BRANCH"
	SCRIPT_SOURCE="$SCRIPT_BRANCH@unknown"
}
Pin_Script_Repo(){
	_psr_branch="${SCRIPT_BRANCH_OVERRIDE:-$1}"
	_psr_ok=false
	if [ "$#" -ge 2 ]; then
		_psr_sha="$2"; _psr_ok=true
	elif _psr_sha="$(/usr/sbin/curl -fsL --retry 3 -H 'Accept: application/vnd.github.sha' \
		"https://api.github.com/repos/$SCRIPT_REPOSITORY/commits/$_psr_branch")"; then
		_psr_ok=true
	fi
	if [ "$_psr_ok" = true ] && printf '%s' "$_psr_sha" | grep -Eq '^[0-9a-f]{40}$'; then
		SCRIPT_BRANCH="$_psr_branch"
		SCRIPT_REVISION="$_psr_sha"
		SCRIPT_REPO="https://raw.githubusercontent.com/$SCRIPT_REPOSITORY/$SCRIPT_REVISION"
		SCRIPT_SOURCE="$SCRIPT_BRANCH@$(printf '%s' "$SCRIPT_REVISION" | cut -c1-7)"
	else
		if [ -n "$SCRIPT_BRANCH_OVERRIDE" ] || [ "$#" -ge 2 ]; then
			Print_Output true "Cannot resolve an exact $SCRIPT_REPOSITORY/$_psr_branch revision; stopping before downloads" "$ERR"
			return 1
		fi
		Print_Output true "Could not look up the latest $_psr_branch commit - installing from the branch instead" "$WARN"
		Unpinned_Script_Repo "$_psr_branch"
	fi
	SCRIPT_UPDATE_READY=true
}

Ensure_Update_Source(){
	[ "$SCRIPT_UPDATE_READY" = true ] || Pin_Script_Repo "${SCRIPT_BRANCH_OVERRIDE:-main}"
}

Script_Source_Identity(){
	printf '%s|%s|%s' "$SCRIPT_REPOSITORY" "$SCRIPT_BRANCH" "${SCRIPT_REVISION:-unknown}"
}

Load_Installed_Source(){
	if [ -n "${VPNMGR_INSTALL_SHA:-}" ]; then
		Pin_Script_Repo "${VPNMGR_INSTALL_BRANCH:-$SCRIPT_BRANCH}" "$VPNMGR_INSTALL_SHA" || return 1
	else
		[ -f "$SCRIPT_SOURCE_REVISION_FILE" ] || return 1
		IFS='|' read -r _lis_repo _lis_branch _lis_sha < "$SCRIPT_SOURCE_REVISION_FILE" || return 1
		[ "$_lis_repo" = "$SCRIPT_REPOSITORY" ] && [ -n "$_lis_branch" ] || return 1
		if [ "$_lis_sha" = unknown ] && [ -z "$SCRIPT_BRANCH_OVERRIDE" ]; then
			# Ordinary API-failure fallback is explicitly unpinned. Reentry must
			# not relabel an already installed branch script as a newly found SHA.
			Unpinned_Script_Repo "$_lis_branch"
		else
			Pin_Script_Repo "$_lis_branch" "$_lis_sha" || return 1
		fi
	fi
	# Installed provenance repairs this build; a later update chooses a new tip.
	SCRIPT_UPDATE_READY=false
}

Resolve_Installed_Source(){
	if Load_Installed_Source; then return 0; fi
	[ -z "${VPNMGR_INSTALL_SHA:-}" ] || return 1
	# Strict builds require installed provenance; never adopt an unrelated tip.
	[ -z "$SCRIPT_BRANCH_OVERRIDE" ] || {
		Print_Output true "Missing exact test-build revision; rerun the normal repo install" "$ERR"
		return 1
	}
	# Older updaters did not record a full revision. Only adopt a candidate when
	# its script bytes match the script already running, before repairing assets.
	Pin_Script_Repo "$SCRIPT_BRANCH" || return 1
	SCRIPT_UPDATE_READY=false
	if [ -z "$SCRIPT_REVISION" ]; then
		# Retain historical ordinary branch fallback, visibly unverified. Strict
		# override builds and supplied SHAs cannot reach this compatibility path.
		Record_Install_Source
		return $?
	fi
	_ris_file="$(mktemp /tmp/vpnmgr-source.XXXXXX)" || return 1
	if ! Download_File "$SCRIPT_REPO/$SCRIPT_NAME.sh" "$_ris_file" || ! cmp -s "$_ris_file" "/jffs/scripts/$SCRIPT_NAME"; then
		rm -f "$_ris_file"
		Print_Output true "Installed script revision is unverified; use forceupdate for a coherent refresh" "$WARN"
		return 1
	fi
	rm -f "$_ris_file"
	Record_Install_Source || return 1
	SCRIPT_UPDATE_READY=false
}

Configure_Test_Providers(){
	if [ "${VPNMGR_TEST_PROVIDERS+x}" = x ]; then
		_ctp_selection="$VPNMGR_TEST_PROVIDERS"
	elif [ -n "$SCRIPT_BRANCH_OVERRIDE" ] && [ -n "$SCRIPT_REVISION" ]; then
		# Pinned branch builds expose NordVPN for testing without status promotion.
		_ctp_selection=nordvpn
	else
		return 0
	fi
	case "$_ctp_selection" in
		nordvpn) printf '%s\n' nordvpn > "$SCRIPT_TEST_PROVIDER_FILE" ;;
		'') rm -f "$SCRIPT_TEST_PROVIDER_FILE" ;;
		*) Print_Output true "Unsupported test-provider selection" "$ERR"; return 1 ;;
	esac
}

Provider_WebUI_Enabled(){
	[ "$2" != ACTIVE ] || return 0
	[ "$1" = nordvpn ] || return 1
	case "$2" in UNTESTED|API_TESTED) grep -qx nordvpn "$SCRIPT_TEST_PROVIDER_FILE" 2>/dev/null ;; *) return 1 ;; esac
}

Select_Install_Source(){
	if [ -n "${VPNMGR_INSTALL_SHA:-}" ]; then
		Pin_Script_Repo "${VPNMGR_INSTALL_BRANCH:-$SCRIPT_BRANCH}" "$VPNMGR_INSTALL_SHA"
	else
		Pin_Script_Repo "$SCRIPT_BRANCH"
	fi
}

Bootstrap_Install(){
	# A normal branch download may race a newer branch tip. Verify the running
	# script against the ONE selected revision before any install/config writes.
	# The ordinary unpinned compatibility path must not reexec a moving branch.
	[ -n "$SCRIPT_REVISION" ] || return 0
	_bis_file="$(mktemp /jffs/scripts/.vpnmgr-bootstrap.XXXXXX)" || return 1
	if ! Download_File "$SCRIPT_REPO/$SCRIPT_NAME.sh" "$_bis_file" ||
		! grep -qF h0me5k1n "$_bis_file" || ! sh -n "$_bis_file"; then
		rm -f "$_bis_file"
		Print_Output true "Cannot verify the selected install script; stopping before installation" "$ERR"
		return 1
	fi
	if cmp -s "$_bis_file" "$0"; then
		rm -f "$_bis_file"
		return 0
	fi
	chmod 0755 "$_bis_file" && mv -f "$_bis_file" "/jffs/scripts/$SCRIPT_NAME" || { rm -f "$_bis_file"; return 1; }
	VPNMGR_INSTALL_SHA="$SCRIPT_REVISION" VPNMGR_INSTALL_BRANCH="$SCRIPT_BRANCH" exec "/jffs/scripts/$SCRIPT_NAME" install
}

# Records where the script just installed came from, for the CLI header and
# WebUI. Installs from main show only the version, so the record is removed.
Record_Install_Source(){
	if [ -n "$SCRIPT_SOURCE" ]; then
		Script_Source_Identity > "$SCRIPT_SOURCE_REVISION_FILE" || return 1
		printf '\n' >> "$SCRIPT_SOURCE_REVISION_FILE" || return 1
	else
		rm -f "$SCRIPT_SOURCE_REVISION_FILE" || return 1
	fi
	if [ -n "$SCRIPT_SOURCE" ] && { [ "${SCRIPT_SOURCE%%@*}" != "main" ] || [ -z "$SCRIPT_REVISION" ]; }; then
		printf '%s\n' "$SCRIPT_SOURCE" > "$SCRIPT_SOURCE_FILE"
		Set_Version_Custom_Settings source "$SCRIPT_SOURCE"
	else
		rm -f "$SCRIPT_SOURCE_FILE"
		Set_Version_Custom_Settings source ""
	fi
}

Update_Check(){
	Ensure_Update_Source || return 1
	echo 'var updatestatus = "InProgress";' > "$SCRIPT_WEB_DIR/detect_update.js"
	doupdate="false"
	localver=$(grep "SCRIPT_VERSION=" "/jffs/scripts/$SCRIPT_NAME" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
	_uc_file="$(mktemp "$SCRIPT_DIR/.update-check.XXXXXX")" || return 1
	if ! Download_File "$SCRIPT_REPO/$SCRIPT_NAME.sh" "$_uc_file" || ! grep -qF h0me5k1n "$_uc_file"; then
		rm -f "$_uc_file"; Print_Output true "Cannot retrieve a valid update script" "$ERR"; return 1
	fi
	serverver="$(grep 'SCRIPT_VERSION=' "$_uc_file" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')" || { rm -f "$_uc_file"; return 1; }
	if [ "$localver" != "$serverver" ]; then
		doupdate="version"
		Set_Version_Custom_Settings server "$serverver"
		echo 'var updatestatus = "'"$serverver"'";'  > "$SCRIPT_WEB_DIR/detect_update.js"
	else
		localmd5="$(md5sum "/jffs/scripts/$SCRIPT_NAME" | awk '{print $1}')"
		remotemd5="$(md5sum "$_uc_file" | awk '{print $1}')"
		if [ "$localmd5" != "$remotemd5" ]; then
			doupdate="md5"
			Set_Version_Custom_Settings server "$serverver-hotfix"
			echo 'var updatestatus = "'"$serverver-hotfix"'";'  > "$SCRIPT_WEB_DIR/detect_update.js"
		fi
	fi
	if [ "$doupdate" = "false" ] && [ -n "$SCRIPT_REVISION" ] &&
		{ [ "$(cat "$SCRIPT_SOURCE_REVISION_FILE" 2>/dev/null)" != "$(Script_Source_Identity)" ] ||
		  [ "$(cat "$SCRIPT_FILES_SOURCE" 2>/dev/null)" != "$(Script_Source_Identity)" ]; }; then
		doupdate="source"
		Set_Version_Custom_Settings server "$serverver-hotfix"
		echo 'var updatestatus = "'"$serverver-hotfix"'";' > "$SCRIPT_WEB_DIR/detect_update.js"
	fi
	if [ "$doupdate" = "false" ]; then
		echo 'var updatestatus = "None";'  > "$SCRIPT_WEB_DIR/detect_update.js"
	fi
	rm -f "$_uc_file"
	echo "$doupdate,$localver,$serverver"
}

Update_Version(){
	# Select outside Update_Check's command substitution and retain one candidate
	# for every script/provider/asset request made by this operation.
	Pin_Script_Repo "${3:-${SCRIPT_BRANCH_OVERRIDE:-main}}" || return 1
	Configure_Test_Providers || return 1
	if [ -z "$1" ]; then
		updatecheckresult="$(Update_Check)" || return 1
		isupdate="$(echo "$updatecheckresult" | cut -f1 -d',')"
		localver="$(echo "$updatecheckresult" | cut -f2 -d',')"
		serverver="$(echo "$updatecheckresult" | cut -f3 -d',')"
		
		if [ "$isupdate" = "version" ]; then
			Print_Output true "New version of $SCRIPT_NAME available - $serverver" "$PASS"
		elif [ "$isupdate" = "md5" ]; then
			Print_Output true "MD5 hash of $SCRIPT_NAME does not match - hotfix available $serverver" "$PASS"
		elif [ "$isupdate" = "source" ]; then
			Print_Output true "A different source revision of $SCRIPT_NAME is available - hotfix $serverver" "$PASS"
		fi
		
		if [ "$isupdate" != "false" ]; then
			printf "\\n${BOLD}Do you want to continue with the update? (y/n)${CLEARFORMAT}  "
			read -r confirm
			case "$confirm" in
				y|Y)
					Update_Addon_Files "$serverver" || return 1
					printf "\\n"
					if /usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" -o "/jffs/scripts/$SCRIPT_NAME"; then
						Print_Output true "$SCRIPT_NAME successfully updated"
						Record_Install_Source || return 1
					else
						return 1
					fi
					chmod 0755 "/jffs/scripts/$SCRIPT_NAME"
					Set_Version_Custom_Settings local "$serverver"
					Set_Version_Custom_Settings server "$serverver"
					Clear_Lock
					PressEnter
					VPNMGR_INSTALL_SHA="$SCRIPT_REVISION" VPNMGR_INSTALL_BRANCH="$SCRIPT_BRANCH" exec "$0"
					exit 0
				;;
				*)
					printf "\\n"
					Clear_Lock
					return 1
				;;
			esac
			exit 0
		else
			Print_Output true "No updates available - latest is $localver" "$WARN"
			Clear_Lock
		fi
	fi
	
	if [ "$1" = "force" ]; then
		_uv_script="$(/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh")" || return 1
		serverver="$(printf '%s\n' "$_uv_script" | grep 'SCRIPT_VERSION=' | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')" || return 1
		Print_Output true "Downloading latest version ($serverver) of $SCRIPT_NAME" "$PASS"
		Update_Addon_Files "$serverver" || return 1
		if /usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" -o "/jffs/scripts/$SCRIPT_NAME"; then
			Print_Output true "$SCRIPT_NAME successfully updated"
			Record_Install_Source || return 1
		else
			return 1
		fi
		chmod 0755 "/jffs/scripts/$SCRIPT_NAME"
		Set_Version_Custom_Settings local "$serverver"
		Set_Version_Custom_Settings server "$serverver"
		Clear_Lock
		if [ -z "$2" ]; then
			PressEnter
			VPNMGR_INSTALL_SHA="$SCRIPT_REVISION" VPNMGR_INSTALL_BRANCH="$SCRIPT_BRANCH" exec "$0"
		elif [ "$2" = "unattended" ]; then
			VPNMGR_INSTALL_SHA="$SCRIPT_REVISION" VPNMGR_INSTALL_BRANCH="$SCRIPT_BRANCH" exec "$0" postupdate
		fi
		exit 0
	fi
}

Update_File(){
	if [ "$1" = "web-assets" ]; then
		Download_Asset "$SCRIPT_REPO/www/jquery.js" "$SCRIPT_WWW_DIR/jquery.js" || return 1
		Download_Asset "$SCRIPT_REPO/www/detect.js" "$SCRIPT_WWW_DIR/detect.js" || return 1
		Print_Output true "Web assets updated" "$PASS"
	elif [ "$1" = "vpnmgr_www.asp" ]; then
		tmpfile="$(mktemp "$SCRIPT_DIR/.$1.XXXXXX")" || return 1
		Download_File "$SCRIPT_REPO/$1" "$tmpfile" || { rm -f "$tmpfile"; return 1; }
		if ! diff -q "$tmpfile" "$SCRIPT_DIR/$1" >/dev/null 2>&1; then
			if [ -f "$SCRIPT_DIR/$1" ]; then
				Get_WebUI_Page "$SCRIPT_DIR/$1"
				sed -i "\\~$MyPage~d" /tmp/menuTree.js
				rm -f "$SCRIPT_WEBPAGE_DIR/$MyPage" 2>/dev/null
			fi
			cp -f "$tmpfile" "$SCRIPT_DIR/$1" || { rm -f "$tmpfile"; return 1; }
			Print_Output true "New version of $1 downloaded" "$PASS"
			Mount_WebUI || { rm -f "$tmpfile"; return 1; }
		fi
		rm -f "$tmpfile"
	elif [ "$1" = "vpnmgr_www.js" ]; then
		tmpfile="$(mktemp "$SCRIPT_DIR/.$1.XXXXXX")" || return 1
		Download_File "$SCRIPT_REPO/$1" "$tmpfile" || { rm -f "$tmpfile"; return 1; }
		if ! diff -q "$tmpfile" "$SCRIPT_DIR/$1" >/dev/null 2>&1; then
			cp -f "$tmpfile" "$SCRIPT_DIR/$1" || { rm -f "$tmpfile"; return 1; }
			Print_Output true "New version of $1 downloaded" "$PASS"
		fi
		cp -f "$SCRIPT_DIR/$1" "$SCRIPT_WEB_DIR/$1" || { rm -f "$tmpfile"; return 1; }
		rm -f "$tmpfile"
	else
		return 1
	fi
}

# vpnmgr_www.js and the provider modules are downloaded separately from the
# script itself. $1 is the version they were fetched for, recorded so that
# Sync_Addon_Files can tell when they are out of step with the script.
Update_Addon_Files(){
	if Update_File web-assets && Update_File vpnmgr_www.asp && Update_File vpnmgr_www.js && Install_Providers; then
		printf '%s\n' "$1" > "$SCRIPT_FILES_VERSION" || return 1
		Script_Source_Identity > "$SCRIPT_FILES_SOURCE" || return 1
	else
		Print_Output true "Failed to refresh WebUI and provider files - will retry when $SCRIPT_NAME is next opened" "$WARN"
		return 1
	fi
}

# Versions up to v3.3.0 did not refresh these files on update, and the updater
# that runs is always the outgoing version's, so catch up here on first run.
Sync_Addon_Files(){
	Resolve_Installed_Source || return 1
	if [ "$(cat "$SCRIPT_FILES_VERSION" 2>/dev/null)" != "$SCRIPT_VERSION" ] ||
		[ "$(cat "$SCRIPT_FILES_SOURCE" 2>/dev/null)" != "$(Script_Source_Identity)" ]; then
		Print_Output true "Refreshing WebUI and provider files for $SCRIPT_VERSION"
		Update_Addon_Files "$SCRIPT_VERSION"
	fi
}

Auto_Startup(){
	case $1 in
		create)
			if [ -f /jffs/scripts/services-start ]; then
				STARTUPLINECOUNT=$(grep -c '# '"${SCRIPT_NAME}_startup" /jffs/scripts/services-start)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"${SCRIPT_NAME}_startup"'/d' /jffs/scripts/services-start
				fi
			fi
			if [ -f /jffs/scripts/post-mount ]; then
				STARTUPLINECOUNT=$(grep -c '# '"${SCRIPT_NAME}_startup" /jffs/scripts/post-mount)
				STARTUPLINECOUNTEX=$(grep -cx "/jffs/scripts/$SCRIPT_NAME startup"' "$@" & # '"$SCRIPT_NAME" /jffs/scripts/post-mount)
				
				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }; then
					sed -i -e '/# '"${SCRIPT_NAME}_startup"'/d' /jffs/scripts/post-mount
				fi
				
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]; then
					echo "/jffs/scripts/$SCRIPT_NAME startup"' "$@" & # '"${SCRIPT_NAME}_startup" >> /jffs/scripts/post-mount
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/post-mount
				echo "" >> /jffs/scripts/post-mount
				echo "/jffs/scripts/$SCRIPT_NAME startup"' "$@" & # '"${SCRIPT_NAME}_startup" >> /jffs/scripts/post-mount
				chmod 0755 /jffs/scripts/post-mount
			fi
		;;
		delete)
			if [ -f /jffs/scripts/services-start ]; then
				STARTUPLINECOUNT=$(grep -c '# '"${SCRIPT_NAME}_startup" /jffs/scripts/services-start)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"${SCRIPT_NAME}_startup"'/d' /jffs/scripts/services-start
				fi
			fi
			if [ -f /jffs/scripts/post-mount ]; then
				STARTUPLINECOUNT=$(grep -c '# '"${SCRIPT_NAME}_startup" /jffs/scripts/post-mount)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"${SCRIPT_NAME}_startup"'/d' /jffs/scripts/post-mount
				fi
			fi
		;;
	esac
}

Auto_ServiceEvent(){
	case $1 in
		create)
			if [ -f /jffs/scripts/service-event ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/service-event)
				STARTUPLINECOUNTEX=$(grep -cx 'if echo "$2" | /bin/grep -q "'"$SCRIPT_NAME"'"; then { /jffs/scripts/'"$SCRIPT_NAME"' service_event "$@" & }; fi # '"$SCRIPT_NAME" /jffs/scripts/service-event)
				
				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/service-event
				fi
				
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]; then
					echo 'if echo "$2" | /bin/grep -q "'"$SCRIPT_NAME"'"; then { /jffs/scripts/'"$SCRIPT_NAME"' service_event "$@" & }; fi # '"$SCRIPT_NAME" >> /jffs/scripts/service-event
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/service-event
				echo "" >> /jffs/scripts/service-event
				echo 'if echo "$2" | /bin/grep -q "'"$SCRIPT_NAME"'"; then { /jffs/scripts/'"$SCRIPT_NAME"' service_event "$@" & }; fi # '"$SCRIPT_NAME" >> /jffs/scripts/service-event
				chmod 0755 /jffs/scripts/service-event
			fi
		;;
		delete)
			if [ -f /jffs/scripts/service-event ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/service-event)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/service-event
				fi
			fi
		;;
	esac
}

Auto_Cron(){
	case $1 in
		create)
			STARTUPLINECOUNT=$(cru l | grep -c "${SCRIPT_NAME}_countrydata")
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "${SCRIPT_NAME}_countrydata"
			fi
		
			STARTUPLINECOUNT=$(cru l | grep -c "${SCRIPT_NAME}_cacheddata")
			if [ "$STARTUPLINECOUNT" -eq 0 ]; then
				cru a "${SCRIPT_NAME}_cacheddata" "0 0 * * * /jffs/scripts/$SCRIPT_NAME refreshcacheddata"
			fi
		;;
		delete)
			STARTUPLINECOUNT=$(cru l | grep -c "${SCRIPT_NAME}_cacheddata")
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "${SCRIPT_NAME}_cacheddata"
			fi
		;;
	esac
}

Download_File(){
	/usr/sbin/curl -fsL --retry 3 "$1" -o "$2"
}

Download_Asset(){
	_da_file="$(mktemp "$2.XXXXXX")" || return 1
	if Download_File "$1" "$_da_file" && chmod 0644 "$_da_file" && mv -f "$_da_file" "$2"; then
		return 0
	fi
	rm -f "$_da_file"
	return 1
}

Get_WebUI_Page(){
	MyPage="none"
	for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
		page="/www/user/user$i.asp"
		if [ -f "$page" ] && [ "$(md5sum < "$1")" = "$(md5sum < "$page")" ]; then
			MyPage="user$i.asp"
			return
		elif [ "$MyPage" = "none" ] && [ ! -f "$page" ]; then
			MyPage="user$i.asp"
		fi
	done
}

### function based on @dave14305's FlexQoS webconfigpage function ###
Get_WebUI_URL(){
	urlpage=""
	urlproto=""
	urldomain=""
	urlport=""

	# Read the served tree; the /tmp working copy can differ from the active mount.
	urlpage="$(sed -nE "/$SCRIPT_NAME/ s/.*url\: \"(user[0-9]+\.asp)\".*/\1/p" /www/require/modules/menuTree.js)"
	if [ "$(nvram get http_enable)" -eq 1 ]; then
		urlproto="https"
	else
		urlproto="http"
	fi
	if [ -n "$(nvram get lan_domain)" ]; then
		urldomain="$(nvram get lan_hostname).$(nvram get lan_domain)"
	else
		urldomain="$(nvram get lan_ipaddr)"
	fi
	if [ "$(nvram get ${urlproto}_lanport)" -eq 80 ] || [ "$(nvram get ${urlproto}_lanport)" -eq 443 ]; then
		urlport=""
	else
		urlport=":$(nvram get ${urlproto}_lanport)"
	fi

	if echo "$urlpage" | grep -qE "user[0-9]+\.asp"; then
		echo "${urlproto}://${urldomain}${urlport}/${urlpage}" | tr "A-Z" "a-z"
	else
		echo "WebUI page not found"
	fi
}
### ###

### locking mechanism code credit to Martineau (@MartineauUK) ###
Mount_WebUI(){
	Print_Output true "Mounting WebUI tab for $SCRIPT_NAME" "$PASS"
	LOCKFILE=/tmp/addonwebui.lock
	FD=386
	eval exec "$FD>$LOCKFILE"
	flock -x "$FD"
	Get_WebUI_Page "$SCRIPT_DIR/vpnmgr_www.asp"
	if [ "$MyPage" = "none" ]; then
		Print_Output true "Unable to mount $SCRIPT_NAME WebUI page, exiting" "$CRIT"
		flock -u "$FD"
		return 1
	fi
	cp -f "$SCRIPT_DIR/vpnmgr_www.asp" "$SCRIPT_WEBPAGE_DIR/$MyPage"
	echo "$SCRIPT_NAME" > "$SCRIPT_WEBPAGE_DIR/$(echo $MyPage | cut -f1 -d'.').title"
	
	if [ "$(uname -o)" = "ASUSWRT-Merlin" ]; then
		if [ ! -f "/tmp/menuTree.js" ]; then
			cp -f "/www/require/modules/menuTree.js" "/tmp/"
		fi
		
		sed -i "\\~$MyPage~d" /tmp/menuTree.js
		sed -i "/url: \"Advanced_OpenVPNClient_Content.asp\", tabName:/a {url: \"$MyPage\", tabName: \"$SCRIPT_NAME\"}," /tmp/menuTree.js
		
		umount /www/require/modules/menuTree.js 2>/dev/null
		mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
	fi
	flock -u "$FD"
	Print_Output true "Mounted $SCRIPT_NAME WebUI page as $MyPage" "$PASS"
}

Validate_Number(){
	if [ "$1" -eq "$1" ] 2>/dev/null; then
		return 0
	else
		return 1
	fi
}

### Searchable picker for country/city selection ###
# The caller puts the candidate names (one per line, already sorted) in
# PICK_LIST and calls Picker_Choose. State is kept in PICK_* globals rather
# than passed through subshells, so the INT trap still fires while a key
# read is pending.

# Picker_Filter [exact]
# Reads names on stdin and prints those containing $PICK_QUERY, ignoring
# case, spaces and punctuation. Literal substring match, input order kept.
# With "exact", prints only names equal to the query after normalising.
Picker_Filter(){
	PICKER_Q="$PICK_QUERY" PICKER_MODE="${1:-}" awk '
		function norm(s){ s=tolower(s); gsub(/[ \t.,_()\/\047-]/,"",s); return s }
		BEGIN { q=norm(ENVIRON["PICKER_Q"]); exact=(ENVIRON["PICKER_MODE"]=="exact") }
		{
			n=norm($0)
			if(exact){ if(n==q) print }
			else if(q=="" || index(n,q)) print
		}
	'
}

Picker_Refilter(){
	PICK_MATCHES="$(printf '%s\n' "$PICK_LIST" | Picker_Filter)"
	if [ -z "$PICK_MATCHES" ]; then
		PICK_COUNT=0
	else
		PICK_COUNT=$(($(printf '%s\n' "$PICK_MATCHES" | wc -l)))
	fi
	PICK_SEL=0
}

# Picker_Resolve
# Sets PICK_RESULT and returns 0 if the query identifies exactly one name:
# a single match, or one name equal to the query (so "Niger" can be chosen
# even though "Nigeria" also matches).
Picker_Resolve(){
	if [ "$PICK_COUNT" -eq 1 ]; then
		PICK_RESULT="$PICK_MATCHES"
		return 0
	fi
	_pr_exact="$(printf '%s\n' "$PICK_MATCHES" | Picker_Filter exact)"
	if [ -n "$_pr_exact" ] && [ "$(printf '%s\n' "$_pr_exact" | wc -l)" -eq 1 ]; then
		PICK_RESULT="$_pr_exact"
		return 0
	fi
	return 1
}

# Picker_HandleKey token [char]
# Applies one key to the picker state. No terminal I/O.
# PICK_SEL is the highlighted match (0 = none); typing always edits the
# query and clears the highlight, Tab/arrows move it without touching the query.
Picker_HandleKey(){
	PICK_MSG=""
	case "$1" in
		CHAR)
			PICK_QUERY="$PICK_QUERY$2"
			Picker_Refilter
		;;
		BS)
			PICK_QUERY="${PICK_QUERY%?}"
			Picker_Refilter
		;;
		TAB|DOWN)
			if [ "$PICK_COUNT" -gt 0 ]; then
				PICK_SEL=$((PICK_SEL % PICK_COUNT + 1))
			fi
		;;
		BTAB|UP)
			if [ "$PICK_COUNT" -gt 0 ]; then
				if [ "$PICK_SEL" -le 1 ]; then
					PICK_SEL="$PICK_COUNT"
				else
					PICK_SEL=$((PICK_SEL - 1))
				fi
			fi
		;;
		ENTER)
			if [ "$PICK_SEL" -gt 0 ]; then
				PICK_RESULT="$(printf '%s\n' "$PICK_MATCHES" | sed -n "${PICK_SEL}p")"
				PICK_DONE="ok"
			elif [ -z "$PICK_QUERY" ]; then
				if [ "$PICK_ALLOW_BLANK" = "true" ]; then
					PICK_RESULT=""
					PICK_DONE="ok"
				else
					PICK_MSG="A selection is required. Type a name, or press Tab to browse."
				fi
			elif [ "$PICK_COUNT" -eq 0 ]; then
				PICK_MSG="No matches. Edit the name, or clear it and press Tab to browse."
			elif Picker_Resolve; then
				PICK_DONE="ok"
			else
				PICK_MSG="Multiple matches. Keep typing, or press Tab to choose one."
			fi
		;;
		ESC|EOF)
			PICK_DONE="cancel"
		;;
	esac
	return 0
}

Picker_ReadByte(){
	PICK_CHAR="$(dd bs=1 count=1 2>/dev/null; printf x)"
	PICK_CHAR="${PICK_CHAR%x}"
}

# Picker_ReadKey
# Reads one keypress from the terminal (already in raw mode) and sets
# PICK_KEY to a Picker_HandleKey token, or IGNORE. PICK_CHAR holds the
# character for CHAR.
Picker_ReadKey(){
	Picker_ReadByte
	case "$PICK_CHAR" in
		"") PICK_KEY="EOF" ;;
		"$PICK_C_NL"|"$PICK_C_CR") PICK_KEY="ENTER" ;;
		"$PICK_C_TAB") PICK_KEY="TAB" ;;
		"$PICK_C_DEL"|"$PICK_C_BS") PICK_KEY="BS" ;;
		"$PICK_C_ESC")
			# Wait briefly for the rest of an escape sequence; none means a bare Esc
			stty min 0 time 1
			Picker_ReadByte
			case "$PICK_CHAR" in
				"") PICK_KEY="ESC" ;;
				"["|O)
					_rk_final=""
					while true; do
						Picker_ReadByte
						[ -z "$PICK_CHAR" ] && break
						_rk_final="$PICK_CHAR"
						case "$PICK_CHAR" in
							[A-Za-z~]) break ;;
						esac
					done
					case "$_rk_final" in
						A) PICK_KEY="UP" ;;
						B) PICK_KEY="DOWN" ;;
						Z) PICK_KEY="BTAB" ;;
						*) PICK_KEY="IGNORE" ;;
					esac
				;;
				*) PICK_KEY="IGNORE" ;;
			esac
			stty min 1 time 0
		;;
		[[:cntrl:]]) PICK_KEY="IGNORE" ;;
		*) PICK_KEY="CHAR" ;;
	esac
}

# Picker_Render
# Redraws the query line and, below it, any message and the visible window
# of matches, then puts the cursor back at the end of the query.
Picker_Render(){
	printf '\r\033[J%s > %s' "$PICK_LABEL" "$PICK_QUERY"
	_rd_lines=0
	if [ -n "$PICK_MSG" ]; then
		printf '\n\033[31m%s\033[0m' "$PICK_MSG"
		_rd_lines=1
	fi
	if [ -n "$PICK_QUERY" ] || [ "$PICK_SEL" -gt 0 ]; then
		if [ "$PICK_COUNT" -eq 0 ]; then
			if [ -z "$PICK_MSG" ]; then
				printf '\n  (no matches)'
				_rd_lines=$((_rd_lines + 1))
			fi
		else
			printf '%s\n' "$PICK_MATCHES" | awk -v sel="$PICK_SEL" -v rows="$PICK_ROWS" -v cols="$PICK_COLS" -v total="$PICK_COUNT" '
				BEGIN {
					top=sel-int(rows/2)
					if(top>total-rows+1) top=total-rows+1
					if(top<1) top=1
				}
				NR>=top && NR<top+rows {
					name=substr($0,1,cols-4)
					if(NR==sel) printf "\n\033[7m> %s\033[0m", name
					else printf "\n  %s", name
				}
				END { if(total>rows) printf "\n  (%d-%d of %d)", top, top+rows-1, total }
			'
			if [ "$PICK_COUNT" -gt "$PICK_ROWS" ]; then
				_rd_lines=$((_rd_lines + PICK_ROWS + 1))
			else
				_rd_lines=$((_rd_lines + PICK_COUNT))
			fi
		fi
	fi
	[ "$_rd_lines" -gt 0 ] && printf '\033[%dA' "$_rd_lines"
	printf '\r\033[%dC' "$((${#PICK_LABEL} + 3 + ${#PICK_QUERY}))"
}

# Picker_Select label allow_blank
# Live type-to-filter picker over PICK_LIST. Sets PICK_RESULT (empty when a
# blank entry is allowed and chosen).
# Returns 0 on a choice, 1 if cancelled, 2 if the terminal cannot support it.
Picker_Select(){
	if [ ! -t 0 ] || [ ! -t 1 ] || [ "${TERM:-dumb}" = "dumb" ]; then
		return 2
	fi
	PICK_STTY="$(stty -g 2>/dev/null)"
	[ -z "$PICK_STTY" ] && return 2
	# isig is left on so that Ctrl+C still reaches the INT trap
	if ! stty -icanon -echo min 1 time 0 2>/dev/null; then
		stty "$PICK_STTY" 2>/dev/null
		PICK_STTY=""
		return 2
	fi

	PICK_LABEL="$1"
	_ps_label_lc="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
	PICK_ALLOW_BLANK="$2"
	PICK_QUERY=""
	PICK_MSG=""
	PICK_DONE=""
	PICK_RESULT=""
	PICK_C_NL='
'
	PICK_C_CR="$(printf '\r')"
	PICK_C_TAB="$(printf '\t')"
	PICK_C_ESC="$(printf '\033')"
	PICK_C_DEL="$(printf '\177')"
	PICK_C_BS="$(printf '\010')"
	_ps_size="$(stty size 2>/dev/null)"
	PICK_ROWS="${_ps_size%% *}"
	PICK_COLS="${_ps_size##* }"
	Validate_Number "$PICK_ROWS" || PICK_ROWS=24
	Validate_Number "$PICK_COLS" || PICK_COLS=80
	PICK_ROWS=$((PICK_ROWS - 4))
	[ "$PICK_ROWS" -gt 10 ] && PICK_ROWS=10
	[ "$PICK_ROWS" -lt 3 ] && PICK_ROWS=3
	Picker_Refilter

	if [ "$PICK_ALLOW_BLANK" = "true" ]; then
		printf "\\n${BOLD}Select a %s${CLEARFORMAT} - type to filter, Tab to browse, Enter to confirm (blank for no preference), Esc to cancel\\n" "$_ps_label_lc"
	else
		printf "\\n${BOLD}Select a %s${CLEARFORMAT} - type to filter, Tab to browse, Enter to confirm, Esc to cancel\\n" "$_ps_label_lc"
	fi

	while [ -z "$PICK_DONE" ]; do
		Picker_Render
		Picker_ReadKey
		[ "$PICK_KEY" = "IGNORE" ] || Picker_HandleKey "$PICK_KEY" "$PICK_CHAR"
	done

	printf '\r\033[J'
	stty "$PICK_STTY" 2>/dev/null
	PICK_STTY=""
	[ "$PICK_DONE" = "cancel" ] && return 1
	printf '%s: %s\n' "$PICK_LABEL" "${PICK_RESULT:-No preference}"
	return 0
}

# Picker_Fallback label allow_blank
# Line-based equivalent of Picker_Select for terminals that cannot do raw
# key reads: a numbered list that can be narrowed by typing part of a name.
# Same PICK_RESULT and return codes as Picker_Select (never returns 2).
Picker_Fallback(){
	PICK_QUERY=""
	PICK_RESULT=""
	_pf_label_lc="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
	Picker_Refilter
	while true; do
		printf "\\n${BOLD}Please select a %s:${CLEARFORMAT}\\n" "$_pf_label_lc"
		printf '%s\n' "$PICK_MATCHES" | awk -v total="$PICK_COUNT" '
			{ lines[NR]=$0 }
			END {
				half=int((total+1)/2)
				for(i=1;i<=half;i++){
					printf "  %3d. %-35s", i, lines[i]
					if(i+half<=total) printf "  %3d. %s", i+half, lines[i+half]
					printf "\n"
				}
			}
		'

		if [ "$2" = "true" ]; then
			printf "\\nEnter a number, part of a name to filter, or leave blank for no preference (e to exit):  "
		else
			printf "\\nEnter a number, or part of a name to filter (e to exit):  "
		fi
		read -r _pf_input || return 1

		if [ "$_pf_input" = "e" ]; then
			return 1
		elif [ -z "$_pf_input" ]; then
			[ "$2" = "true" ] && return 0
			PICK_QUERY=""
			Picker_Refilter
		elif Validate_Number "$_pf_input"; then
			if [ "$_pf_input" -lt 1 ] || [ "$_pf_input" -gt "$PICK_COUNT" ]; then
				printf "\\n\\e[31mPlease enter a number between 1 and %s${CLEARFORMAT}\\n" "$PICK_COUNT"
			else
				PICK_RESULT="$(printf '%s\n' "$PICK_MATCHES" | sed -n "${_pf_input}p")"
				return 0
			fi
		else
			PICK_QUERY="$_pf_input"
			Picker_Refilter
			if [ "$PICK_COUNT" -eq 0 ]; then
				printf "\\n\\e[31mNo %s matches '%s'${CLEARFORMAT}\\n" "$_pf_label_lc" "$_pf_input"
				PICK_QUERY=""
				Picker_Refilter
			elif Picker_Resolve; then
				return 0
			fi
		fi
	done
}

# Picker_Choose label allow_blank
Picker_Choose(){
	Picker_Select "$1" "$2"
	_pc_rc=$?
	if [ "$_pc_rc" -eq 2 ]; then
		Picker_Fallback "$1" "$2"
		_pc_rc=$?
	fi
	return "$_pc_rc"
}
### End of searchable picker ###

# ParseSlotSelection raw_input
# Accepts a single slot ("3"), a range ("1-5"), or a comma list ("1,4,2"),
# any combination thereof. Validates 1-5 bounds, rejects reversed ranges,
# dedupes in first-occurrence order. On success sets $GLOBAL_VPN_SLOTS to
# a space-separated, ordered, deduped list and returns 0. Returns 1 on
# any malformed/out-of-range input, leaving $GLOBAL_VPN_SLOTS unset.
ParseSlotSelection(){
	_pss_raw="$1"
	[ -z "$_pss_raw" ] && return 1
	case "$_pss_raw" in *[!0-9,-]*) return 1 ;; esac

	_pss_result=""
	_pss_remaining="$_pss_raw"
	_pss_more="true"
	while [ "$_pss_more" = "true" ]; do
		case "$_pss_remaining" in
			*,*)
				_pss_tok="${_pss_remaining%%,*}"
				_pss_remaining="${_pss_remaining#*,}"
			;;
			*)
				_pss_tok="$_pss_remaining"
				_pss_more="false"
			;;
		esac
		# A plain ,-split-then-word-split would silently swallow empty
		# fields (e.g. "1,,2" -> "1 2", or a trailing "1,2," -> "1 2"),
		# so reject them explicitly instead.
		[ -z "$_pss_tok" ] && return 1

		case "$_pss_tok" in
			*-*-*) return 1 ;;
			*-*)
				_pss_lo="${_pss_tok%%-*}"; _pss_hi="${_pss_tok##*-}"
				[ -z "$_pss_lo" ] || [ -z "$_pss_hi" ] && return 1
				Validate_Number "$_pss_lo" && Validate_Number "$_pss_hi" || return 1
				{ [ "$_pss_lo" -lt 1 ] || [ "$_pss_lo" -gt 5 ] || [ "$_pss_hi" -lt 1 ] || [ "$_pss_hi" -gt 5 ]; } && return 1
				[ "$_pss_lo" -gt "$_pss_hi" ] && return 1
				_pss_n="$_pss_lo"
				while [ "$_pss_n" -le "$_pss_hi" ]; do
					_pss_result="$_pss_result $_pss_n"
					_pss_n=$((_pss_n + 1))
				done
			;;
			*)
				Validate_Number "$_pss_tok" || return 1
				{ [ "$_pss_tok" -lt 1 ] || [ "$_pss_tok" -gt 5 ]; } && return 1
				_pss_result="$_pss_result $_pss_tok"
			;;
		esac
	done

	_pss_deduped=""
	for _pss_n in $_pss_result; do
		case " $_pss_deduped " in
			*" $_pss_n "*) ;;
			*) _pss_deduped="$_pss_deduped $_pss_n" ;;
		esac
	done
	[ -z "$_pss_deduped" ] && return 1
	GLOBAL_VPN_SLOTS="${_pss_deduped# }"
	return 0
}

Conf_FromSettings(){
	SETTINGSFILE="/jffs/addons/custom_settings.txt"
	TMPFILE="/tmp/vpnmgr_settings.txt"
	if [ -f "$SETTINGSFILE" ]; then
		if [ "$(grep "vpnmgr_" $SETTINGSFILE | grep -v "version" -c)" -gt 0 ]; then
			Print_Output true "Updated settings from WebUI found, merging into $SCRIPT_CONF" "$PASS"
			cp -a "$SCRIPT_CONF" "$SCRIPT_CONF.bak"
			grep "vpnmgr_" "$SETTINGSFILE" | grep -v "version" > "$TMPFILE"
			sed -i "s/vpnmgr_//g;s/ /=/g" "$TMPFILE"
			while IFS='' read -r line || [ -n "$line" ]; do
				SETTINGNAME="$(echo "$line" | cut -f1 -d'=')"
				SETTINGVALUE="$(echo "$line" | cut -f2- -d'=' | sed "s/=/ /g")"
				SETTINGVPNNO="$(echo "$SETTINGNAME" | cut -f1 -d'_' | sed 's/vpn//g')"
				if echo "$SETTINGNAME" | grep -q "usn"; then
					nvram set vpn_client"$SETTINGVPNNO"_username="$SETTINGVALUE"
				elif echo "$SETTINGNAME" | grep -q "pwd"; then
					nvram set vpn_client"$SETTINGVPNNO"_password="$SETTINGVALUE"
				else
					sed -i "s~$SETTINGNAME=.*~$SETTINGNAME=$SETTINGVALUE~" "$SCRIPT_CONF"
				fi
			done < "$TMPFILE"
			grep 'vpnmgr_version' "$SETTINGSFILE" > "$TMPFILE"
			sed -i "\\~vpnmgr_~d" "$SETTINGSFILE"
			mv "$SETTINGSFILE" "$SETTINGSFILE.bak"
			cat "$SETTINGSFILE.bak" "$TMPFILE" > "$SETTINGSFILE"
			rm -f "$TMPFILE"
			rm -f "$SETTINGSFILE.bak"
			nvram commit
			Print_Output true "Merge of updated settings from WebUI completed successfully" "$PASS"
		else
			Print_Output false "No updated settings from WebUI found, no merge into $SCRIPT_CONF necessary" "$PASS"
		fi
	fi
}

# WebUI request state is kept outside persistent configuration and contains no secrets.
Runtime_Init(){
	VPNMGR_RUNTIME_DIR="${VPNMGR_RUNTIME_DIR:-/tmp/vpnmgr-runtime}"
	VPNMGR_PRIVATE_DIR="${VPNMGR_RUNTIME_DIR%/}-private"
	mkdir -p "$VPNMGR_RUNTIME_DIR" "$VPNMGR_PRIVATE_DIR" || return 1
	chmod 700 "$VPNMGR_PRIVATE_DIR" || return 1
	# Retain only recent completed request files, never an active reservation.
	find "$VPNMGR_RUNTIME_DIR" -maxdepth 1 -type f -name 'detection_*.json' -mtime +1 -exec rm -f {} \; 2>/dev/null
	find "$VPNMGR_RUNTIME_DIR" -maxdepth 1 -type f -name 'apply_*.json' -mtime +1 2>/dev/null | while IFS= read -r _rt_old; do
		case "$(cat "$_rt_old" 2>/dev/null)" in *'"state":"done"'*|*'"state":"failed"'*|*'"state":"busy"'*|*'"state":"superseded"'*) rm -f "$_rt_old" ;; esac
	done
}
Runtime_ValidID(){
	case "$1" in ''|*[!0-9]*) return 1 ;; esac
	[ "${#1}" -le 32 ]
}
Runtime_Write(){
	# The temporary file is a sibling so readers only observe complete JSON.
	_rt_file="$1"; shift
	_rt_tmp="$VPNMGR_RUNTIME_DIR/.${_rt_file}.$$"
	(umask 022; printf '%s\n' "$1" > "$_rt_tmp") && mv -f "$_rt_tmp" "$VPNMGR_RUNTIME_DIR/$_rt_file" || { rm -f "$_rt_tmp"; return 1; }
}
Runtime_Detect(){
	Runtime_ValidID "$1" && Runtime_Init || return 1
	_rt_id="$1"
	Detect_OpenVPN_Runtime
	Runtime_Write "detection_${_rt_id}.json" "{\"request\":\"$_rt_id\",\"state\":\"done\",\"version\":\"$OVPN_RUNTIME_VERSION\",\"number\":\"$OVPN_RUNTIME_NUMBER\",\"family\":\"$OVPN_RUNTIME_FAMILY\",\"status\":\"$OVPN_RUNTIME_STATUS\"}"
}
Runtime_Status(){
	_rt_clients=""; _rt_n=1
	while [ "$_rt_n" -le 5 ]; do
		_rt_s=pending; _rt_c=unknown
		eval "_rt_s=\${_apply_status_$_rt_n:-pending}; _rt_c=\${_apply_connection_$_rt_n:-unknown}"
		[ -z "$_rt_clients" ] || _rt_clients="$_rt_clients,"
		_rt_clients="$_rt_clients{\"slot\":$_rt_n,\"status\":\"$_rt_s\",\"connection\":\"$_rt_c\"}"
		_rt_n=$((_rt_n + 1))
	done
	Runtime_Write "apply_${_apply_id}.json" "{\"request\":\"$_apply_id\",\"state\":\"$_apply_state\",\"merged\":${_apply_merged:-false},\"clients\":[$_rt_clients],\"message\":\"$_apply_message\"}"
}
Runtime_Release(){
	[ "$(cat "$VPNMGR_RUNTIME_DIR/apply.lock/owner" 2>/dev/null)" = "$_apply_id" ] || return 1
	rm -f "$VPNMGR_RUNTIME_DIR/apply.lock/owner" "$VPNMGR_RUNTIME_DIR/apply.lock/ready.$_apply_id"
	rmdir "$VPNMGR_RUNTIME_DIR/apply.lock"
}
Runtime_Recover(){
(
	Runtime_ValidID "$1" && Runtime_Init || return 1
	_apply_id="$1"
	[ "$(cat "$VPNMGR_RUNTIME_DIR/apply.lock/owner" 2>/dev/null)" = "$_apply_id" ] || return 0
	_rr_ready="$VPNMGR_RUNTIME_DIR/apply.lock/ready.$_apply_id"
	_rr_stamp="$(cat "$_rr_ready" 2>/dev/null)"
	case "$_rr_stamp" in ''|*[!0-9]*) return 0 ;; esac
	[ $(($(date +%s) - _rr_stamp)) -ge 60 ] || return 0
	_rr_claim="$VPNMGR_RUNTIME_DIR/apply.lock/expired.$_apply_id.$$"
	# Request-specific tokens prevent an old process claiming a newer lock.
	# This rename competes atomically with Apply; running work is never expired.
	mv "$_rr_ready" "$_rr_claim" 2>/dev/null || return 0
	_apply_state=failed; _apply_message=expired; _apply_merged=false
	for _apply_init in 1 2 3 4 5; do eval "_apply_status_$_apply_init=pending; _apply_connection_$_apply_init=unknown"; done
	if ! Runtime_Status; then
		# Retain a recoverable reservation when publication fails; never tell the
		# browser to unlock its form without an authoritative terminal result.
		mv "$_rr_claim" "$_rr_ready" 2>/dev/null || :
		return 1
	fi
	rm -f "$_rr_claim" || return 1
	Runtime_Release
)
}
Runtime_Prepare(){
	Runtime_ValidID "$1" && Runtime_Init || return 1
	_apply_id="$1"; _apply_merged=false; _apply_message=busy; _apply_state=busy
	for _apply_init in 1 2 3 4 5; do eval "_apply_status_$_apply_init=pending; _apply_connection_$_apply_init=unknown"; done
	# Never overwrite the state of a repeated request, including completed work.
	[ ! -f "$VPNMGR_RUNTIME_DIR/apply_${_apply_id}.json" ] || return 0
	if ! mkdir "$VPNMGR_RUNTIME_DIR/apply.lock" 2>/dev/null; then
		_rt_expired_id="$(cat "$VPNMGR_RUNTIME_DIR/apply.lock/owner" 2>/dev/null)"
		if Runtime_ValidID "$_rt_expired_id"; then Runtime_Recover "$_rt_expired_id" || return 1; fi
		mkdir "$VPNMGR_RUNTIME_DIR/apply.lock" 2>/dev/null || { Runtime_Status; return $?; }
	fi
	(umask 077; printf '%s\n' "$_apply_id" > "$VPNMGR_RUNTIME_DIR/apply.lock/owner" && date +%s > "$VPNMGR_RUNTIME_DIR/apply.lock/ready.$_apply_id") || { Runtime_Release; return 1; }
	_apply_state=ready; _apply_message=ready
	Runtime_Status || { Runtime_Release; return 1; }
}
Runtime_Merge(){
	_rm_snapshot="$1"; _rm_id="$2"; _rm_shared="${VPNMGR_SETTINGS_FILE:-/jffs/addons/custom_settings.txt}"
	_rm_tmp="$VPNMGR_PRIVATE_DIR/merge.$$"; _rm_conf="$VPNMGR_PRIVATE_DIR/config.$$"
	cp -a "$SCRIPT_CONF" "$SCRIPT_CONF.bak" || return 1
	cp "$SCRIPT_CONF" "$_rm_conf" || return 1
	while IFS= read -r _rm_line || [ -n "$_rm_line" ]; do
		case "$_rm_line" in vpnmgr_vpn[1-5]_*) ;; *) continue ;; esac
		_rm_key="${_rm_line%% *}"; _rm_value="${_rm_line#* }"; _rm_key="${_rm_key#vpnmgr_}"
		case "$_rm_key" in
			vpn[1-5]_usn|vpn[1-5]_pwd)
				_rm_slot="${_rm_key#vpn}"; _rm_slot="${_rm_slot%%_*}"
				case "$_rm_key" in *_usn) _rm_field=username ;; *) _rm_field=password ;; esac
				nvram set "vpn_client${_rm_slot}_${_rm_field}=$_rm_value" || { rm -f "$_rm_conf"; return 1; } ;;
			*)
				# Pass the value via a file, not awk -v, which interprets escapes.
				printf '%s\n' "$_rm_value" > "$_rm_tmp" || { rm -f "$_rm_conf"; return 1; }
				awk -v key="$_rm_key" 'NR==FNR { value=$0; next } index($0,key "=")==1 { print key "=" value; next } { print }' "$_rm_tmp" "$_rm_conf" > "$_rm_conf.next" && mv "$_rm_conf.next" "$_rm_conf" || { rm -f "$_rm_tmp" "$_rm_conf" "$_rm_conf.next"; return 1; } ;;
		esac
	done < "$_rm_snapshot"
	rm -f "$_rm_tmp"
	cp "$_rm_conf" "$SCRIPT_CONF" && nvram commit || { rm -f "$_rm_conf"; return 1; }
	rm -f "$_rm_conf"
	# Never consume a newer tab's submission.
	[ "$(awk '$1=="vpnmgr_request_id" {print $2; n++} END {if(n!=1) print "invalid"}' "$_rm_shared" 2>/dev/null)" = "$_rm_id" ] || return 2
	awk '$1 !~ /^vpnmgr_/ || $1 ~ /^vpnmgr_version/' "$_rm_shared" > "$_rm_tmp" || return 1
	[ "$(awk '$1=="vpnmgr_request_id" {print $2; n++} END {if(n!=1) print "invalid"}' "$_rm_shared" 2>/dev/null)" = "$_rm_id" ] || { rm -f "$_rm_tmp"; return 2; }
	cat "$_rm_tmp" > "$_rm_shared" || { rm -f "$_rm_tmp"; return 1; }
	rm -f "$_rm_tmp"
	return 0
}
Runtime_Apply(){
(
	Runtime_ValidID "$1" && Runtime_Init || return 1
	_apply_id="$1"; _apply_merged=false; _apply_message=unreserved; _apply_state=failed
	for _apply_init in 1 2 3 4 5; do eval "_apply_status_$_apply_init=pending; _apply_connection_$_apply_init=unknown"; done
	[ "$(cat "$VPNMGR_RUNTIME_DIR/apply.lock/owner" 2>/dev/null)" = "$_apply_id" ] || { [ -f "$VPNMGR_RUNTIME_DIR/apply_${_apply_id}.json" ] || Runtime_Status; return 1; }
	_apply_terminal=false
	_apply_snapshot="$VPNMGR_PRIVATE_DIR/settings.$_apply_id.$$"
	trap 'Runtime_Apply_Cleanup' EXIT
	trap 'exit 1' HUP INT TERM
	# Atomic claim competes with expiry and duplicate event execution.
	mv "$VPNMGR_RUNTIME_DIR/apply.lock/ready.$_apply_id" "$VPNMGR_RUNTIME_DIR/apply.lock/running.$_apply_id.$$" 2>/dev/null || return 0
	_apply_state=running; _apply_message=running
	Runtime_Status || { _apply_message=status_failed; return 1; }
	if ! (umask 077; cp "${VPNMGR_SETTINGS_FILE:-/jffs/addons/custom_settings.txt}" "$_apply_snapshot"); then
		_apply_state=failed; _apply_message=snapshot_failed
	elif [ "$(awk '$1=="vpnmgr_request_id" {print $2; n++} END {if(n!=1) print "invalid"}' "$_apply_snapshot")" != "$_apply_id" ]; then
		_apply_state=superseded; _apply_message=nonce_mismatch
	else
		if Runtime_Merge "$_apply_snapshot" "$_apply_id"; then _apply_rc=0; else _apply_rc=$?; fi
		case "$_apply_rc" in 0) _apply_merged=true ;; 2) _apply_merged=true; _apply_state=superseded; _apply_message=superseded ;; *) _apply_state=failed; _apply_message=merge_failed ;; esac
	fi
	rm -f "$_apply_snapshot"
	if [ "$_apply_merged" = true ] && [ "$_apply_state" = running ]; then
		for _apply_slot in 1 2 3 4 5; do
			_apply_managed="$(grep "^vpn${_apply_slot}_managed=" "$SCRIPT_CONF" | cut -f2- -d=)"
			if [ "$_apply_managed" = true ]; then
				eval "_apply_status_$_apply_slot=applying"; Runtime_Status || { _apply_message=status_failed; return 1; }
				_apply_slot_rc=0
				ManageVPN "$_apply_slot" || _apply_slot_rc=1
				case "$(grep "^vpn${_apply_slot}_schenabled=" "$SCRIPT_CONF" | cut -f2- -d=)" in
					true) ScheduleVPN "$_apply_slot" || _apply_slot_rc=1 ;; false) CancelScheduleVPN "$_apply_slot" || _apply_slot_rc=1 ;;
				esac
				UpdateVPNConfig unattended "$_apply_slot" || _apply_slot_rc=1
				if [ "$_apply_slot_rc" = 0 ]; then eval "_apply_status_$_apply_slot=applied"; else eval "_apply_status_$_apply_slot=failed"; fi
				eval "_apply_connection_$_apply_slot=\${VPNMGR_UPDATE_CONNECTION:-unknown}"
			else
				if [ "$_apply_managed" = false ]; then UnmanageVPN "$_apply_slot" || { eval "_apply_status_$_apply_slot=failed"; Runtime_Status || { _apply_message=status_failed; return 1; }; continue; }; fi
				eval "_apply_status_$_apply_slot=unmanaged; _apply_connection_$_apply_slot=not_requested"
			fi
			Runtime_Status || { _apply_message=status_failed; return 1; }
		done
		_apply_state="done"; _apply_message=complete
	fi
	Runtime_Status || { _apply_message=status_failed; return 1; }
	_apply_terminal=true
)
}
Runtime_Apply_Cleanup(){
	[ -f "$VPNMGR_RUNTIME_DIR/apply.lock/running.$_apply_id.$$" ] || return 0
	rm -f "$_apply_snapshot" "$VPNMGR_PRIVATE_DIR/merge.$$" "$VPNMGR_PRIVATE_DIR/config.$$" "$VPNMGR_PRIVATE_DIR/config.$$.next"
	if [ "$(cat "$VPNMGR_RUNTIME_DIR/apply.lock/owner" 2>/dev/null)" = "$_apply_id" ]; then
		if [ "$_apply_terminal" != true ]; then
			_apply_state=failed
			[ "$_apply_message" = status_failed ] || _apply_message=interrupted
			Runtime_Status || :
		fi
		rm -f "$VPNMGR_RUNTIME_DIR/apply.lock/running.$_apply_id.$$"
		Runtime_Release || :
	fi
}

Create_Dirs(){
	if [ ! -d "$SCRIPT_DIR" ]; then
		mkdir -p "$SCRIPT_DIR"
	fi
	
	if [ ! -d "$OVPN_ARCHIVE_DIR" ]; then
		mkdir -p "$OVPN_ARCHIVE_DIR"
	fi

	if [ ! -d "$PROVIDERS_DIR" ]; then
		mkdir -p "$PROVIDERS_DIR"
	fi

	if [ ! -d "$SCRIPT_WWW_DIR" ]; then
		mkdir -p "$SCRIPT_WWW_DIR"
	fi
	
	if [ ! -d "$SCRIPT_WEBPAGE_DIR" ]; then
		mkdir -p "$SCRIPT_WEBPAGE_DIR"
	fi
	
	if [ ! -d "$SCRIPT_WEB_DIR" ]; then
		mkdir -p "$SCRIPT_WEB_DIR"
	fi
}

Create_Symlinks(){
	rm -rf "${SCRIPT_WEB_DIR:?}/"* 2>/dev/null
	
	ln -s "$SCRIPT_DIR/config" "$SCRIPT_WEB_DIR/config.htm" 2>/dev/null

	printf '' > "$SCRIPT_DIR/providers_list"
	for _pfile in "$PROVIDERS_DIR/provider_"*.sh; do
		[ -f "$_pfile" ] || continue
		_pbase="$(basename "$_pfile")"
		_pid="${_pbase#provider_}"; _pid="${_pid%.sh}"
		_pname="$(grep "^# Display:" "$_pfile" | sed 's/^# Display: //')"
		_pstatus="$(grep "^# Status:" "$_pfile" | awk '{print $3}')"
		if Provider_WebUI_Enabled "$_pid" "$_pstatus"; then
			printf '%s|%s\n' "$_pid" "$_pname" >> "$SCRIPT_DIR/providers_list"
			ln -s "$SCRIPT_DIR/${_pid}_countrydata" "$SCRIPT_WEB_DIR/${_pid}_countrydata.htm" 2>/dev/null
		fi
	done
	ln -s "$SCRIPT_DIR/providers_list" "$SCRIPT_WEB_DIR/providers.htm" 2>/dev/null

	cp -f "$SCRIPT_DIR/vpnmgr_www.js" "$SCRIPT_WEB_DIR/vpnmgr_www.js" 2>/dev/null || return 1

	Runtime_Init && ln -s "$VPNMGR_RUNTIME_DIR" "$SCRIPT_WEB_DIR/runtime" 2>/dev/null || return 1

	ln -s /tmp/detect_vpnmgr.js "$SCRIPT_WEB_DIR/detect_vpnmgr.js" 2>/dev/null
	ln -s /tmp/vpnmgrserverloads "$SCRIPT_WEB_DIR/vpnmgrserverloads.js" 2>/dev/null

	if [ ! -d "$SCRIPT_WEB_DIR/www" ]; then
		ln -s "$SCRIPT_WWW_DIR" "$SCRIPT_WEB_DIR/www" 2>/dev/null
	fi
}

Install_Providers(){
	mkdir -p "$PROVIDERS_DIR"
	_ip_rc=0
	# shellcheck disable=SC2043
	for provider in nordvpn; do
		_ip_file="$(mktemp "$PROVIDERS_DIR/.provider_${provider}.XXXXXX")" || return 1
		if Download_File "$SCRIPT_REPO/providers/provider_${provider}.sh" "$_ip_file" &&
			chmod 0755 "$_ip_file" && mv -f "$_ip_file" "$PROVIDERS_DIR/provider_${provider}.sh"; then
			:
		else
			rm -f "$_ip_file"
			_ip_rc=1
		fi
	done
	return "$_ip_rc"
}

Refresh_Provider_Cache(){
	configured_providers=""
	for i in 1 2 3 4 5; do
		prov="$(grep "vpn${i}_provider" "$SCRIPT_CONF" | cut -f2 -d"=" | tr 'A-Z' 'a-z')"
		if [ -n "$prov" ] && ! printf '%s' "$configured_providers" | grep -qF "$prov"; then
			configured_providers="${configured_providers} ${prov}"
		fi
	done
	for prov in $configured_providers; do
		if Load_Provider "$prov"; then
			"provider_${prov}_refresh_cache"
		fi
	done
}

Conf_Exists(){
	if [ -f "$SCRIPT_CONF" ]; then
		dos2unix "$SCRIPT_CONF"
		chmod 0644 "$SCRIPT_CONF"
		sed -i -e 's/"//g' "$SCRIPT_CONF"
		if ! grep -q "_customsettings" "$SCRIPT_CONF"; then
			for i in 1 2 3 4 5; do
				sed -i '/^vpn'"$i"'_type=.*/a vpn'"$i"'_customsettings=true' "$SCRIPT_CONF"
			done
		fi
		if ! grep -q "_mute" "$SCRIPT_CONF"; then
			for i in 1 2 3 4 5; do
				sed -i '/^vpn'"$i"'_customsettings=.*/a vpn'"$i"'_mute=20' "$SCRIPT_CONF"
			done
		fi
		if ! grep -q "_debugverb" "$SCRIPT_CONF"; then
			for i in 1 2 3 4 5; do
				sed -i '/^vpn'"$i"'_mute=.*/a vpn'"$i"'_debugverb=false' "$SCRIPT_CONF"
			done
		fi
		return 0
	else
		for i in 1 2 3 4 5; do
			{
				echo "##### VPN Client $i #####"
				echo "vpn${i}_managed=false"
				echo "vpn${i}_provider=NordVPN"
				echo "vpn${i}_protocol=UDP"
				echo "vpn${i}_type=Standard"
				echo "vpn${i}_customsettings=true"
				echo "vpn${i}_mute=20"
				echo "vpn${i}_debugverb=false"
				echo "vpn${i}_schenabled=false"
				echo "vpn${i}_schdays=*"
				echo "vpn${i}_schhours=0"
				echo "vpn${i}_schmins=$i"
				echo "vpn${i}_countryname="
				echo "vpn${i}_cityname="
				echo "vpn${i}_countryid=0"
				echo "vpn${i}_cityid=0"
				echo "#########################"
			} >> "$SCRIPT_CONF"
		done
		return 1
	fi
}

getIP(){
	echo "$1" | grep "^remote " | head -1 | cut -f2 -d' '
}

getPort(){
	echo "$1" | grep "^remote " | head -1 | cut -f3 -d' '
}

getCipher(){
	echo "$1" | grep "^cipher " | cut -f2 -d' '
}

getAuthDigest(){
	echo "$1" | grep "^auth " | cut -f2 -d' '
}

Normalize_OVPN_Profile(){
	# Provider profiles can use CRLF; line endings are not option/key content.
	printf '%s\n' "$1" | tr -d '\r'
}

getClientCA(){
	echo "$1" | awk '/<ca>/{flag=1;next}/<\/ca>/{flag=0}flag' | sed '/^#/ d'
}

getConnectState(){
	nvram get vpn_client"$1"_state
}

CompareArchiveContents(){
	archiveschanged="false"
	FILES="$1"
	for f in $FILES; do
		if [ -f "$f" ]; then
			if [ -f "$OVPN_ARCHIVE_DIR/$(basename "$f")" ]; then
				remotemd5="$(md5sum "$f" | awk '{print $1}')"
				localmd5="$(md5sum "$OVPN_ARCHIVE_DIR/$(basename "$f")" | awk '{print $1}')"
				if [ "$localmd5" != "$remotemd5" ]; then
					mv "$f" "$OVPN_ARCHIVE_DIR/$(basename "$f")"
					archiveschanged="true"
				else
					rm -f "$f"
				fi
			else
				mv "$f" "$OVPN_ARCHIVE_DIR/$(basename "$f")"
				archiveschanged="true"
			fi
		fi
	done
	echo "$archiveschanged"
}

ListVPNClients(){
	showload="$1"
	showunmanaged="$2"
	
	if [ "$showload" = "true" ]; then
		printf "Checking server loads...\\n\\n"
	fi
	
	printf "VPN client list:\\n\\n"
	for i in 1 2 3 4 5; do
		VPN_CLIENTDESC="$(nvram get vpn_client"$i"_desc)"
		if [ "$showload" = "true" ]; then
			if [ -z "$VPN_CLIENTDESC" ]; then
				continue
			fi
		fi
		MANAGEDSTATE=""
		CONNECTSTATE=""
		SCHEDULESTATE=""
		CUSTOMSETTINGSTATE=""
		if [ "$(grep "vpn${i}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "true" ]; then
			MANAGEDSTATE="${BOLD}${PASS}Managed${CLEARFORMAT}"
		elif [ "$(grep "vpn${i}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
			if [ "$showunmanaged" = "hide" ]; then
				continue
			fi
			MANAGEDSTATE="${BOLD}${ERR}Unmanaged${CLEARFORMAT}"
		fi
		if [ "$(getConnectState "$i")" = "2" ]; then
			CONNECTSTATE="${BOLD}${PASS}Connected${CLEARFORMAT}"
		else
			CONNECTSTATE="${BOLD}${ERR}Disconnected${CLEARFORMAT}"
		fi
		if [ "$(grep "vpn${i}_customsettings" "$SCRIPT_CONF" | cut -f2 -d"=")" = "true" ]; then
			CUSTOMSETTINGSTATE="${SETTING}Customised${CLEARFORMAT}"
		elif [ "$(grep "vpn${i}_customsettings" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
			CUSTOMSETTINGSTATE="${BOLD}Uncustomised${CLEARFORMAT}"
		fi
		if [ "$(grep "vpn${i}_schenabled" "$SCRIPT_CONF" | cut -f2 -d"=")" = "true" ]; then
			SCHEDULESTATE="${SETTING}Scheduled${CLEARFORMAT}"
		elif [ "$(grep "vpn${i}_schenabled" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
			SCHEDULESTATE="${BOLD}Unscheduled${CLEARFORMAT}"
		fi
		COUNTRYNAME="$(grep "vpn${i}_countryname" "$SCRIPT_CONF" | cut -f2 -d"=")"
		[ -z "$COUNTRYNAME" ] && COUNTRYNAME="None"
		CITYNAME="$(grep "vpn${i}_cityname" "$SCRIPT_CONF" | cut -f2 -d"=")"
		[ -z "$CITYNAME" ] && CITYNAME="None"
		
		if [ "$showload" = "true" ]; then
			_ll_prov="$(grep "vpn${i}_provider" "$SCRIPT_CONF" | cut -f2 -d"=" | tr 'A-Z' 'a-z')"
			if Load_Provider "$_ll_prov" 2>/dev/null; then
				SERVERLOAD="$("provider_${_ll_prov}_get_server_load" "$VPN_CLIENTDESC")"
			else
				SERVERLOAD="Unknown"
			fi
		fi
		
		if [ "$(grep "vpn${i}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "true" ]; then
			printf "%s.    $VPN_CLIENTDESC ($MANAGEDSTATE, $SCHEDULESTATE, $CUSTOMSETTINGSTATE, $CONNECTSTATE)\\n" "$i"
		else
			printf "%s.    $VPN_CLIENTDESC ($MANAGEDSTATE, $CONNECTSTATE)\\n" "$i"
		fi
		if [ "$showload" = "true" ]; then
			printf "      Current server load: %s%%\\n" "$SERVERLOAD"
		fi
		printf "      Chosen country: %s - Preferred city: %s\\n\\n" "$COUNTRYNAME" "$CITYNAME"
	done
	printf "\\n"
}

Default_VPN_Data_Ciphers(){
	printf '%s' 'AES-256-GCM:AES-128-GCM:AES-256-CBC:AES-128-CBC'
}

UpdateVPNConfig(){
	VPNMGR_UPDATE_CONNECTION=unknown
	ISUNATTENDED=""
	if [ "$1" = "unattended" ]; then
		ISUNATTENDED="true"
		shift
	fi
	VPN_NO="$1"
	PRIOR_CONN_STATE="$2"
	if [ -z "$PRIOR_CONN_STATE" ]; then
		PRIOR_CONN_STATE="$(getConnectState "$VPN_NO")"
		[ -z "$PRIOR_CONN_STATE" ] && PRIOR_CONN_STATE="0"
	fi
	VPN_PROVIDER="$(grep "vpn${VPN_NO}_provider" "$SCRIPT_CONF" | cut -f2 -d"=")"
	VPN_PROVIDER_LC="$(printf '%s' "$VPN_PROVIDER" | tr 'A-Z' 'a-z')"
	VPN_PROT_SHORT="$(grep "vpn${VPN_NO}_protocol" "$SCRIPT_CONF" | cut -f2 -d"=")"
	VPN_TYPE_SHORT="$(grep "vpn${VPN_NO}_type" "$SCRIPT_CONF" | cut -f2 -d"=")"
	VPN_COUNTRYID="$(grep "vpn${VPN_NO}_countryid" "$SCRIPT_CONF" | cut -f2 -d"=")"
	VPN_COUNTRYNAME="$(grep "vpn${VPN_NO}_countryname" "$SCRIPT_CONF" | cut -f2 -d"=")"
	VPN_CITYID="$(grep "vpn${VPN_NO}_cityid" "$SCRIPT_CONF" | cut -f2 -d"=")"
	VPN_CITYNAME="$(grep "vpn${VPN_NO}_cityname" "$SCRIPT_CONF" | cut -f2 -d"=")"
	OVPN_ADDR=""
	Detect_OpenVPN_Runtime

	Load_Provider "$VPN_PROVIDER_LC" || return 1

	Print_Output true "Retrieving VPN server for $VPN_PROVIDER (Protocol: $VPN_PROT_SHORT, Type: $VPN_TYPE_SHORT)"

	OVPN_HOSTNAME="$("provider_${VPN_PROVIDER_LC}_get_server" \
		"$VPN_COUNTRYID" "$VPN_COUNTRYNAME" \
		"$VPN_CITYID" "$VPN_CITYNAME" \
		"$VPN_PROT_SHORT" "$VPN_TYPE_SHORT")" || return 1
	[ -z "$OVPN_HOSTNAME" ] && Print_Output true "Could not determine server identifier for VPN client $VPN_NO" "$ERR" && return 1

	OVPN_DETAIL="$("provider_${VPN_PROVIDER_LC}_get_ovpn" "$OVPN_HOSTNAME" "$VPN_PROT_SHORT" "$VPN_TYPE_SHORT" "$OVPN_RUNTIME_FAMILY")" || {
		Print_Output true "Error retrieving VPN server ovpn file" "$ERR"
		return 1
	}
	OVPN_DETAIL="$(Normalize_OVPN_Profile "$OVPN_DETAIL")" || return 1
	[ -z "$OVPN_DETAIL" ] && Print_Output true "Error retrieving VPN server ovpn file" "$ERR" && return 1
	if [ "$VPN_PROVIDER_LC" = nordvpn ]; then
		provider_nordvpn_preflight "$OVPN_DETAIL" || {
			Print_Output true "NordVPN profile has invalid or incomplete CA/TLS key material" "$ERR"
			return 1
		}
	fi

	OVPN_ADDR="$(getIP "$OVPN_DETAIL")"
	case "$OVPN_ADDR" in
		''|*[!a-zA-Z0-9.:_-]*) Print_Output true "Could not determine a valid address for VPN server" "$ERR"; return 1 ;;
	esac
	OVPN_PORT="$(getPort "$OVPN_DETAIL")"
	case "$OVPN_PORT" in
		''|*[!0-9]*) Print_Output true "Error determining port for VPN server" "$ERR"; return 1 ;;
	esac
	[ "$OVPN_PORT" -ge 1 ] && [ "$OVPN_PORT" -le 65535 ] || {
		Print_Output true "Invalid VPN server port" "$ERR"
		return 1
	}
	if [ "$VPN_PROVIDER_LC" = nordvpn ]; then
		OVPN_PROFILE_PROTO="$(printf '%s\n' "$OVPN_DETAIL" | awk '$1 == "proto" { print $2; exit }')"
		case "$VPN_PROT_SHORT:$OVPN_PROFILE_PROTO" in
			UDP:udp|TCP:tcp-client|TCP:tcp) ;;
			*) Print_Output true "NordVPN profile protocol does not match the selected transport" "$ERR"; return 1 ;;
		esac
	fi
	OVPN_CIPHER="$(getCipher "$OVPN_DETAIL")" || :
	OVPN_AUTHDIGEST="$(getAuthDigest "$OVPN_DETAIL")" || :
	OVPN_PROFILE_CIPHERS="$(printf '%s\n' "$OVPN_DETAIL" | awk '$1 == "data-ciphers" || $1 == "ncp-ciphers" { print $2; exit }')"
	case "$OVPN_PROFILE_CIPHERS" in
		*[!a-zA-Z0-9:_-]*) Print_Output true "Invalid VPN profile data-ciphers list" "$ERR"; return 1 ;;
	esac
	VPN_HMAC="$("provider_${VPN_PROVIDER_LC}_get_hmac" "$OVPN_DETAIL")" || {
		Print_Output true "Invalid VPN profile TLS control mode" "$ERR"
		return 1
	}
	case "$VPN_HMAC" in -1|0|1|2|3|4) ;; *) Print_Output true "Invalid VPN profile TLS control mode" "$ERR"; return 1 ;; esac
	if [ "$VPN_PROVIDER_LC" = nordvpn ] && [ "$VPN_HMAC" = 3 ]; then
		[ "$OVPN_RUNTIME_FAMILY" = modern ] || {
			Print_Output true "Modern NordVPN profiles require a detected OpenVPN version of 2.6 or newer" "$ERR"
			return 1
		}
		OVPN_PROFILE_TLS_MIN="$(printf '%s\n' "$OVPN_DETAIL" | awk '$1 == "tls-version-min" { print $2; exit }')"
		case "$OVPN_PROFILE_TLS_MIN" in
			''|1.2) ;;
			*) Print_Output true "NordVPN profile TLS minimum cannot be represented by native OpenVPN defaults" "$ERR"; return 1 ;;
		esac
	fi
	if [ -z "$OVPN_CIPHER" ] || [ -z "$OVPN_AUTHDIGEST" ]; then
		if [ "$VPN_PROVIDER_LC" != nordvpn ] || [ "$VPN_HMAC" != 3 ]; then
			Print_Output true "VPN profile is missing cipher or auth digest" "$ERR"
			return 1
		fi
		# Modern NordVPN leaves data-ciphers and auth at the OpenVPN 2.6+ defaults.
		[ -n "$OVPN_CIPHER" ] || OVPN_CIPHER=default
		[ -n "$OVPN_AUTHDIGEST" ] || OVPN_AUTHDIGEST=default
	fi
	if [ -n "$OVPN_PROFILE_CIPHERS" ]; then
		VPN_NCP_CIPHERS="$OVPN_PROFILE_CIPHERS"
	elif [ "$VPN_PROVIDER_LC" = nordvpn ] && [ "$VPN_HMAC" = 3 ]; then
		VPN_NCP_CIPHERS=""
	else
		VPN_NCP_CIPHERS="$(Default_VPN_Data_Ciphers)"
	fi
	CLIENT_CA="$(getClientCA "$OVPN_DETAIL")"
	[ -z "$CLIENT_CA" ] && Print_Output true "Error determing VPN server Certificate Authority certificate" "$ERR" && return 1
	if [ "$VPN_PROVIDER_LC" = nordvpn ] && [ "$(grep "vpn${VPN_NO}_customsettings" "$SCRIPT_CONF" | cut -f2 -d"=")" != true ]; then
		# Merlin has no native server-role verification field. Keep the user's
		# custom block intact; reject a profile it cannot safely represent.
		if Firmware_Build_Before 386.3; then
			if [ "$(/bin/uname -m)" = aarch64 ]; then
				VPN_EXISTING_CUSTOM="$(printf '%s' "$(nvram get vpn_client"$VPN_NO"_cust2)$(nvram get vpn_client"$VPN_NO"_cust21)$(nvram get vpn_client"$VPN_NO"_cust22)" | openssl base64 -d -A)"
			elif [ "$(uname -o)" = ASUSWRT-Merlin ]; then
				VPN_EXISTING_CUSTOM="$(printf '%s' "$(nvram get vpn_client"$VPN_NO"_cust2)" | openssl base64 -d -A)"
			else
				VPN_EXISTING_CUSTOM="$(nvram get vpn_client"$VPN_NO"_custom)"
			fi
		else
			VPN_EXISTING_CUSTOM="$(cat /jffs/openvpn/vpn_client"$VPN_NO"_custom3 2>/dev/null)"
		fi
		printf '%s\n' "$VPN_EXISTING_CUSTOM" | grep -Eq '^[[:space:]]*remote-cert-tls[[:space:]]+server([[:space:]]|$)' || {
			Print_Output true "VPN client $VPN_NO needs remote-cert-tls server in its user-managed custom options" "$ERR"
			return 1
		}
		if [ "$VPN_HMAC" = 3 ] && printf '%s\n' "$VPN_EXISTING_CUSTOM" | grep -Eq '^[[:space:]]*(tls-auth|tls-crypt|key-direction|cipher|auth)[[:space:]]|^[[:space:]]*tls-version-min[[:space:]]+1\.[01]([[:space:]]|$)'; then
			Print_Output true "VPN client $VPN_NO has custom TLS/cipher options incompatible with the selected tls-crypt profile" "$ERR"
			return 1
		fi
	fi

	OVPN_HOSTNAME_SHORT="$("provider_${VPN_PROVIDER_LC}_get_short_name" "$OVPN_HOSTNAME" "$OVPN_ADDR")" || return 1

	EXISTING_ADDR="$(nvram get vpn_client"$VPN_NO"_addr)"
	EXISTING_PORT="$(nvram get vpn_client"$VPN_NO"_port)"
	EXISTING_PROTO="$(nvram get vpn_client"$VPN_NO"_proto)"
	if [ "$EXISTING_PROTO" = "tcp-client" ]; then
		EXISTING_PROTO="TCP"
	elif [ "$EXISTING_PROTO" = "udp" ]; then
		EXISTING_PROTO="UDP"
	fi

	if [ "$OVPN_ADDR" = "$EXISTING_ADDR" ] && [ "$OVPN_PORT" = "$EXISTING_PORT" ] && [ "$VPN_PROT_SHORT" = "$EXISTING_PROTO" ]; then
		Print_Output true "VPN client $VPN_NO server - unchanged" "$WARN"
	else
		Print_Output true "Updating VPN client $VPN_NO to new $VPN_PROVIDER server"
	fi

	if [ -z "$(nvram get vpn_client"$VPN_NO"_addr)" ]; then
		nvram set vpn_client"$VPN_NO"_adns=3 || return 1
		nvram set vpn_client"$VPN_NO"_enforce=1 || return 1
		if Firmware_Build_Before 384.18; then
			nvram set vpn_client"$VPN_NO"_clientlist="<DummyVPN>172.16.14.1>0.0.0.0>VPN" || return 1
		elif Firmware_Build_Before 386.3; then
			nvram set vpn_client"$VPN_NO"_clientlist="<DummyVPN>172.16.14.1>>VPN" || return 1
		fi
		if ! nvram get vpn_clientx_eas | grep -q "$VPN_NO"; then
			nvram set vpn_clientx_eas="$(nvram get vpn_clientx_eas),$VPN_NO" || return 1
		fi
	fi

	nvram set vpn_client"$VPN_NO"_addr="$OVPN_ADDR" || return 1
	nvram set vpn_client"$VPN_NO"_port="$OVPN_PORT" || return 1
	if [ "$VPN_PROT_SHORT" = "TCP" ]; then
		nvram set vpn_client"$VPN_NO"_proto="tcp-client" || return 1
	elif [ "$VPN_PROT_SHORT" = "UDP" ]; then
		nvram set vpn_client"$VPN_NO"_proto="udp" || return 1
	fi
	VPN_DESC="$("provider_${VPN_PROVIDER_LC}_get_desc" "$OVPN_HOSTNAME" "$OVPN_HOSTNAME_SHORT" "$VPN_PROT_SHORT" "$VPN_TYPE_SHORT")" || return 1
	nvram set vpn_client"$VPN_NO"_desc="$VPN_DESC" || return 1

	nvram set vpn_client"$VPN_NO"_cipher="$OVPN_CIPHER" || return 1
	nvram set vpn_client"$VPN_NO"_crypt="tls" || return 1
	nvram set vpn_client"$VPN_NO"_digest="$OVPN_AUTHDIGEST" || return 1
	nvram set vpn_client"$VPN_NO"_fw=1 || return 1
	nvram set vpn_client"$VPN_NO"_if="tun" || return 1
	nvram set vpn_client"$VPN_NO"_nat=1 || return 1
	nvram set vpn_client"$VPN_NO"_ncp_ciphers="$VPN_NCP_CIPHERS" || return 1
	nvram set vpn_client"$VPN_NO"_ncp_enable=1 || return 1
	nvram set vpn_client"$VPN_NO"_reneg=0 || return 1
	nvram set vpn_client"$VPN_NO"_tlsremote=0 || return 1
	nvram set vpn_client"$VPN_NO"_userauth=1 || return 1
	nvram set vpn_client"$VPN_NO"_useronly=1 || return 1

	VPN_COMP="$("provider_${VPN_PROVIDER_LC}_get_comp")" || return 1
	nvram set vpn_client"$VPN_NO"_comp="$VPN_COMP" || return 1

	nvram set vpn_client"$VPN_NO"_hmac="$VPN_HMAC" || return 1

	if Firmware_Build_Before 384.19; then
		nvram set vpn_client"$VPN_NO"_connretry="-1" || return 1
	else
		nvram set vpn_client"$VPN_NO"_connretry=0 || return 1
	fi

	if [ "$(grep "vpn${VPN_NO}_customsettings" "$SCRIPT_CONF" | cut -f2 -d"=")" = "true" ]; then
		SetVPNCustomSettings "$VPN_NO" "$OVPN_RUNTIME_FAMILY" "$OVPN_RUNTIME_NUMBER" "$OVPN_DETAIL" || {
			Print_Output true "Error writing custom OpenVPN options for VPN client $VPN_NO" "$ERR"
			return 1
		}
	else
		Strip_Stale_X509Name "$VPN_NO" || return 1
	fi

	if [ "$ISUNATTENDED" = "true" ]; then
		if [ -z "$(nvram get vpn_client"$VPN_NO"_username)" ]; then
			Print_Output true "No username set for VPN client $VPN_NO" "$WARN"
		fi

		if [ -z "$(nvram get vpn_client"$VPN_NO"_password)" ]; then
			Print_Output true "No password set for VPN client $VPN_NO" "$WARN"
		fi
	else
		if [ -n "$(nvram get vpn_client"$VPN_NO"_username)" ] && [ -n "$(nvram get vpn_client"$VPN_NO"_password)" ]; then
			while true; do
				printf "${BOLD}Do you want to update the username and password for the VPN client? (y/n)${CLEARFORMAT}  "
				read -r confirm
				case "$confirm" in
					y|Y)
						printf "Please enter username:  "
						read -r vpnusn
						nvram set vpn_client"$VPN_NO"_username="$vpnusn" || return 1
						printf "\\n"
						printf "Please enter password:  "
						read -r vpnpwd
						nvram set vpn_client"$VPN_NO"_password="$vpnpwd" || return 1
						printf "\\n"
						break
					;;
					n|N)
						printf "\\n"
						break
					;;
					*)
						printf "\\n${BOLD}Please enter a valid choice (y/n)${CLEARFORMAT}\\n"
					;;
				esac
			done
		fi

		if [ -z "$(nvram get vpn_client"$VPN_NO"_username)" ]; then
			printf "\\n${BOLD}No username set for VPN client %s${CLEARFORMAT}\\n" "$VPN_NO"
			printf "Please enter username:  "
			read -r vpnusn
			nvram set vpn_client"$VPN_NO"_username="$vpnusn" || return 1
			printf "\\n"
		fi

		if [ -z "$(nvram get vpn_client"$VPN_NO"_password)" ]; then
			printf "\\n${BOLD}No password set for VPN client %s${CLEARFORMAT}\\n" "$VPN_NO"
			printf "Please enter password:  "
			read -r vpnpwd
			nvram set vpn_client"$VPN_NO"_password="$vpnpwd" || return 1
			printf "\\n"
		fi
	fi

	nvram commit || return 1

	"provider_${VPN_PROVIDER_LC}_write_certs" "$VPN_NO" "$OVPN_DETAIL" || return 1

	retry="false"

	if nvram get vpn_clientx_eas | grep -q "$VPN_NO"; then
		VPN_RGW="$(nvram get vpn_client"$VPN_NO"_rgw)"

		VPNMGR_UPDATE_CONNECTION=failed
		RestartVPNClient "$VPN_NO" || return 1

		Print_Output true "Checking that VPN client $VPN_NO establishes a connection ($OVPN_HOSTNAME_SHORT $VPN_TYPE_SHORT $VPN_PROT_SHORT)"
		tunnelup="false"
		for _uv_attempt in 1 2 3; do
			waited=0
			while [ "$waited" -lt 20 ]; do
				if [ "$(getConnectState "$VPN_NO")" = "2" ]; then
					tunnelup="true"
					break
				fi
				sleep 2
				waited=$((waited + 2))
			done
			[ "$tunnelup" = "true" ] && break
			[ "$_uv_attempt" -eq 3 ] || RestartVPNClient "$VPN_NO" || return 1
		done

		[ "$tunnelup" = true ] && VPNMGR_UPDATE_CONNECTION=connected
		if [ "$tunnelup" = "true" ] && [ "$VPN_RGW" = "1" ]; then
			if ! ping -w 10 -I "tun1$VPN_NO" 1.1.1.1 >/dev/null 2>&1; then
				Print_Output true "VPN client $VPN_NO connected but no traffic reached 1.1.1.1 through the tunnel - check routing/firewall ($OVPN_HOSTNAME_SHORT $VPN_TYPE_SHORT $VPN_PROT_SHORT)" "$WARN"
			fi
		fi

		if [ "$tunnelup" = "false" ]; then
			Print_Output true "VPN client $VPN_NO did not connect after 3 attempts, please investigate! ($OVPN_HOSTNAME_SHORT $VPN_TYPE_SHORT $VPN_PROT_SHORT)" "$CRIT"
			if [ "$ISUNATTENDED" != "true" ]; then
				while true; do
					printf "${BOLD}Do you want to vpnmgr to retry? (y/n)${CLEARFORMAT}  "
					read -r confirm
					case "$confirm" in
						y|Y)
							retry="true"
							break
						;;
						n|N)
							printf "\\n"
							break
						;;
						*)
							printf "\\n${BOLD}Please enter a valid choice (y/n)${CLEARFORMAT}\\n"
						;;
					esac
				done
			fi
		else
			Print_Output true "VPN client $VPN_NO is up! ($OVPN_HOSTNAME_SHORT $VPN_TYPE_SHORT $VPN_PROT_SHORT)" "$PASS"
			if [ "$VPN_RGW" != "1" ] && [ "$VPN_RGW" != "2" ] && [ "$VPN_RGW" != "3" ]; then
				Print_Output true "VPN client $VPN_NO is not routing any traffic yet - set 'Redirect Internet traffic through tunnel' to Yes (all) or configure VPN Director in the router WebUI" "$WARN"
			fi
		fi
	else
		VPNMGR_UPDATE_CONNECTION=not_requested
	fi

	if [ "$retry" = "true" ]; then
		UpdateVPNConfig "$VPN_NO" "$PRIOR_CONN_STATE"
		return
	fi

	if [ "$PRIOR_CONN_STATE" != "2" ] && nvram get vpn_clientx_eas | grep -q "$VPN_NO" && [ "$(getConnectState "$VPN_NO")" = "2" ]; then
		Print_Output true "VPN client $VPN_NO was not connected before configuration - stopping it again to restore that state" "$WARN"
		VPNMGR_UPDATE_CONNECTION=unknown
		service stop_vpnclient"$VPN_NO" >/dev/null 2>&1 || return 1
		[ "$(getConnectState "$VPN_NO")" = 0 ] || return 1
		VPNMGR_UPDATE_CONNECTION=verified_stopped
	fi

	[ "$VPNMGR_UPDATE_CONNECTION" != failed ] || return 1
	Print_Output true "VPN client $VPN_NO updated ($OVPN_HOSTNAME_SHORT $VPN_TYPE_SHORT $VPN_PROT_SHORT)" "$PASS"
}

RestartVPNClient(){
	Print_Output true "Restarting VPN client $1"
	service stop_vpnclient"$1" >/dev/null 2>&1 || return 1
	sleep 5
	if [ ! -f /opt/bin/xargs ]; then
		Print_Output true "Installing findutils from Entware"
		opkg update || return 1
		opkg install findutils || return 1
	fi
	ps | grep -v grep | grep -i "openvpn" | grep "client$1" | awk '{print $1}' | xargs kill -9 >/dev/null 2>&1
	service start_vpnclient"$1" >/dev/null 2>&1 || return 1
	sleep 5
}

ManageVPN(){
	VPN_NO="$1"
	
	if [ -z "$(nvram get vpn_client"$VPN_NO"_username)" ] && [ -z "$(nvram get vpn_client"$VPN_NO"_password)" ]; then
		Print_Output false "No credentials set for VPN client $VPN_NO yet - they will be required when you configure it" "$WARN"
	fi

	Print_Output true "Enabling management of VPN client $VPN_NO"
	sed -i 's/^vpn'"$VPN_NO"'_managed.*$/vpn'"$VPN_NO"'_managed=true/' "$SCRIPT_CONF" || return 1
	Print_Output true "Management of VPN client $VPN_NO successfully enabled" "$PASS"
}

UnmanageVPN(){
	VPN_NO="$1"
	
	Print_Output true "Removing management of VPN client $VPN_NO"
	sed -i 's/^vpn'"$VPN_NO"'_managed.*$/vpn'"$VPN_NO"'_managed=false/' "$SCRIPT_CONF" || return 1
	CancelScheduleVPN "$VPN_NO" || return 1
	Print_Output true "Management of VPN client $VPN_NO successfully removed" "$PASS"
}

ScheduleVPN(){
	VPN_NO="$1"
	CRU_DAYNUMBERS="$(grep "vpn${VPN_NO}_schdays" "$SCRIPT_CONF" | cut -f2 -d"=" | sed 's/Sun/0/;s/Mon/1/;s/Tues/2/;s/Wed/3/;s/Thurs/4/;s/Fri/5/;s/Sat/6/;')"
	CRU_HOURS="$(grep "vpn${VPN_NO}_schhours" "$SCRIPT_CONF" | cut -f2 -d"=")"
	CRU_MINUTES="$(grep "vpn${VPN_NO}_schmins" "$SCRIPT_CONF" | cut -f2 -d"=")"
	
	Print_Output true "Configuring scheduled update for VPN client $VPN_NO"
	
	if cru l | grep -q "${SCRIPT_NAME}_VPN${VPN_NO}"; then
		cru d "${SCRIPT_NAME}_VPN${VPN_NO}" || return 1
	fi
	
	cru a "${SCRIPT_NAME}_VPN${VPN_NO}" "$CRU_MINUTES $CRU_HOURS * * $CRU_DAYNUMBERS /jffs/scripts/$SCRIPT_NAME updatevpn $VPN_NO" || return 1
	
	if [ -f /jffs/scripts/services-start ]; then
		sed -i "/${SCRIPT_NAME}_VPN${VPN_NO}/d" /jffs/scripts/services-start || return 1
		echo "cru a ${SCRIPT_NAME}_VPN${VPN_NO} \"$CRU_MINUTES $CRU_HOURS * * $CRU_DAYNUMBERS /jffs/scripts/$SCRIPT_NAME updatevpn $VPN_NO\" # $SCRIPT_NAME" >> /jffs/scripts/services-start || return 1
	else
		echo "#!/bin/sh" > /jffs/scripts/services-start || return 1
		echo "cru a ${SCRIPT_NAME}_VPN${VPN_NO} \"$CRU_MINUTES $CRU_HOURS * * $CRU_DAYNUMBERS /jffs/scripts/$SCRIPT_NAME updatevpn $VPN_NO\" # $SCRIPT_NAME" >> /jffs/scripts/services-start || return 1
		chmod 755 /jffs/scripts/services-start || return 1
	fi
	
	sed -i 's/^vpn'"$VPN_NO"'_schenabled.*$/vpn'"$VPN_NO"'_schenabled=true/' "$SCRIPT_CONF" || return 1
	
	Print_Output true "Scheduled update created for VPN client $VPN_NO" "$PASS"
}

CancelScheduleVPN(){
	VPN_NO="$1"
	
	Print_Output true "Removing scheduled update for VPN client $VPN_NO"
		
	if cru l | grep -q "${SCRIPT_NAME}_VPN${VPN_NO}"; then
		cru d "${SCRIPT_NAME}_VPN${VPN_NO}" || return 1
	fi
	
	sed -i 's/^vpn'"$VPN_NO"'_schenabled.*$/vpn'"$VPN_NO"'_schenabled=false/' "$SCRIPT_CONF" || return 1
	
	if [ -f /jffs/scripts/services-start ] && grep -q "${SCRIPT_NAME}_VPN${VPN_NO}" /jffs/scripts/services-start; then
		sed -i "/${SCRIPT_NAME}_VPN${VPN_NO}/d" /jffs/scripts/services-start || return 1
	fi
	
	Print_Output true "Scheduled update cancelled for VPN client $VPN_NO" "$PASS"
}

Shortcut_Script(){
	case $1 in
		create)
			if [ -d /opt/bin ] && [ ! -f "/opt/bin/$SCRIPT_NAME" ] && [ -f "/jffs/scripts/$SCRIPT_NAME" ]; then
				ln -s "/jffs/scripts/$SCRIPT_NAME" /opt/bin
				chmod 0755 "/opt/bin/$SCRIPT_NAME"
			fi
		;;
		delete)
			if [ -f "/opt/bin/$SCRIPT_NAME" ]; then
				rm -f "/opt/bin/$SCRIPT_NAME"
			fi
		;;
	esac
}

SetVPNClient(){
	vpnpreset="$2"
	ScriptHeader
	ListVPNClients false "$1"
	printf "Choose options as follows:\\n"
	printf "    - VPN client (pick from list)\\n"
	printf "\\n"
	printf "${BOLD}#########################################################${CLEARFORMAT}\\n"

	exitmenu=""
	vpnnum=""

	if [ -n "$vpnpreset" ]; then
		vpnnum="$vpnpreset"
	else
		while true; do
			printf "\\n${BOLD}Please enter the VPN client number (pick from list):${CLEARFORMAT}  "
			read -r vpn_choice

			if [ "$vpn_choice" = "e" ]; then
				exitmenu="exit"
				break
			elif ! Validate_Number "$vpn_choice"; then
				printf "\\n\\e[31mPlease enter a valid number (pick from list)${CLEARFORMAT}\\n"
			else
				if [ "$vpn_choice" -lt 1 ] || [ "$vpn_choice" -gt 5 ]; then
					printf "\\n\\e[31mPlease enter a number between 1 and 5${CLEARFORMAT}\\n"
				else
					vpnnum="$vpn_choice"
					printf "\\n"
					break
				fi
			fi
		done
	fi

	if [ "$exitmenu" != "exit" ]; then
		GLOBAL_VPN_NO="$vpnnum"
		return 0
	else
		printf "\\n"
		return 1
	fi
}

SetVPNParameters(){
	vpnpreset="$1"
	exitmenu=""
	vpnnum=""
	vpnprovider=""
	vpnprot=""
	vpntype=""
	choosecountry=""
	cityblank=""
	countryname=""
	countryid=0
	cityname=""
	cityid=0

	if [ -n "$vpnpreset" ]; then
		vpnnum="$vpnpreset"
	else
		while true; do
			printf "\\n${BOLD}Please enter the VPN client number (pick from list):${CLEARFORMAT}  "
			read -r vpn_choice

			if [ "$vpn_choice" = "e" ]; then
				exitmenu="exit"
				break
			elif ! Validate_Number "$vpn_choice"; then
				printf "\\n\\e[31mPlease enter a valid number (pick from list)${CLEARFORMAT}\\n"
			else
				if [ "$vpn_choice" -lt 1 ] || [ "$vpn_choice" -gt 5 ]; then
					printf "\\n\\e[31mPlease enter a number between 1 and 5${CLEARFORMAT}\\n"
				else
					vpnnum="$vpn_choice"
					printf "\\n"
					break
				fi
			fi
		done
	fi

	if [ "$exitmenu" != "exit" ]; then
		if [ "$(grep "vpn${vpnnum}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
			Print_Output false "VPN client $vpnnum is not managed" "$ERR"
			return 1
		fi
		while true; do
			printf "\\n${BOLD}Please select a VPN provider:${CLEARFORMAT}\\n"
			_provcnt=0
			_provconfigs=""
			for _pf in "$PROVIDERS_DIR"/provider_*.sh; do
				[ -f "$_pf" ] || continue
				_pstatus="$(sed -n '3p' "$_pf")"
				case "$_pstatus" in *DEPRECATED*|*UNMAINTAINED*|*TEMPLATE*) continue ;; esac
				_pdisplay="$(grep '^# Display:' "$_pf" | cut -c12-)"
				_pconfig="$(grep '^# Config:' "$_pf" | cut -c11-)"
				[ -z "$_pdisplay" ] || [ -z "$_pconfig" ] && continue
				_provcnt=$((_provcnt + 1))
				printf "    %d. %s\\n" "$_provcnt" "$_pdisplay"
				_provconfigs="${_provconfigs}${_pconfig}
"
			done
			printf "\\nChoose an option:  "
			read -r provmenu
			case "$provmenu" in
				e)
					exitmenu="exit"
					break
				;;
				*)
					if Validate_Number "$provmenu" && [ "$provmenu" -ge 1 ] && [ "$provmenu" -le "$_provcnt" ]; then
						vpnprovider="$(printf '%s' "$_provconfigs" | sed -n "${provmenu}p")"
						printf "\\n"
						break
					else
						printf "\\n\\e[31mPlease enter a valid choice (1-%s)${CLEARFORMAT}\\n" "$_provcnt"
					fi
				;;
			esac
		done
	fi
	
	if [ "$exitmenu" != "exit" ]; then
		vpnprovider_lc="$(printf '%s' "$vpnprovider" | tr 'A-Z' 'a-z')"
		Load_Provider "$vpnprovider_lc" || { exitmenu="exit"; }
	fi

	if [ "$exitmenu" != "exit" ]; then
		typelist="$("provider_${vpnprovider_lc}_get_types")"
		COUNTYPES="$(printf '%s\n' "$typelist" | wc -l)"
		if [ "$COUNTYPES" -eq 1 ]; then
			vpntype="$(printf '%s\n' "$typelist" | sed -n '1p')"
		else
			while true; do
				printf "\\n${BOLD}Please select a VPN Type:${CLEARFORMAT}\\n"
				printf '%s\n' "$typelist" | awk '{ printf "  %3d. %s\n", NR, $0 }'
				printf "\\nChoose an option:  "
				read -r typemenu

				if [ "$typemenu" = "e" ]; then
					exitmenu="exit"
					break
				elif ! Validate_Number "$typemenu"; then
					printf "\\n\\e[31mPlease enter a valid number (1-%s)${CLEARFORMAT}\\n" "$COUNTYPES"
				elif [ "$typemenu" -lt 1 ] || [ "$typemenu" -gt "$COUNTYPES" ]; then
					printf "\\n\\e[31mPlease enter a number between 1 and %s${CLEARFORMAT}\\n" "$COUNTYPES"
				else
					vpntype="$(printf '%s\n' "$typelist" | sed -n "${typemenu}p")"
					printf "\\n"
					break
				fi
			done
		fi
	fi

	if [ "$exitmenu" != "exit" ]; then
		while true; do
			printf "\\n${BOLD}Please select a VPN protocol:${CLEARFORMAT}\\n"
			printf "    1. UDP\\n"
			printf "    2. TCP\\n\\n"
			printf "Choose an option:  "
			read -r protmenu

			case "$protmenu" in
				1)
					vpnprot="UDP"
					printf "\\n"
					break
				;;
				2)
					vpnprot="TCP"
					printf "\\n"
					break
				;;
				e)
					exitmenu="exit"
					break
				;;
				*)
					printf "\\n\\e[31mPlease enter a valid choice (1-2)${CLEARFORMAT}\\n"
				;;
			esac
		done
	fi

	if [ "$exitmenu" != "exit" ]; then
		if "provider_${vpnprovider_lc}_country_required"; then
			choosecountry="true"
		else
			while true; do
				printf "\\n${BOLD}Would you like to select a country (y/n)?${CLEARFORMAT}  "
				read -r country_select

				if [ "$country_select" = "e" ]; then
					exitmenu="exit"
					break
				elif [ "$country_select" = "n" ] || [ "$country_select" = "N" ]; then
					choosecountry="false"
					printf "\\n"
					break
				elif [ "$country_select" = "y" ] || [ "$country_select" = "Y" ]; then
					choosecountry="true"
					break
				else
					printf "\\n\\e[31mPlease enter y or n${CLEARFORMAT}\\n"
				fi
			done
		fi
	fi

	if [ "$choosecountry" = "true" ]; then
		PICK_LIST="$("provider_${vpnprovider_lc}_get_country_names" | sort -f)"
		[ -z "$PICK_LIST" ] && Print_Output true "Error, country data for $vpnprovider is missing" "$ERR" && return 1
		if Picker_Choose "Country" false; then
			countryname="$PICK_RESULT"
			countryid="$("provider_${vpnprovider_lc}_get_country_id" "$countryname")"
			printf "\\n"
		else
			exitmenu="exit"
		fi

		if [ "$exitmenu" != "exit" ]; then
			citycount="$("provider_${vpnprovider_lc}_get_city_count" "$countryname")"

			if [ "$citycount" -eq 1 ]; then
				cityname="$("provider_${vpnprovider_lc}_get_city_names" "$countryname")"
				cityid="$("provider_${vpnprovider_lc}_get_city_id" "$countryname" "$cityname")"
			elif [ "$citycount" -gt 1 ]; then
				# A blank entry means no city preference, unless the provider needs one
				if "provider_${vpnprovider_lc}_city_required"; then
					cityblank="false"
				else
					cityblank="true"
				fi
				PICK_LIST="$("provider_${vpnprovider_lc}_get_city_names" "$countryname" | sort -f)"
				if Picker_Choose "City" "$cityblank"; then
					if [ -n "$PICK_RESULT" ]; then
						cityname="$PICK_RESULT"
						cityid="$("provider_${vpnprovider_lc}_get_city_id" "$countryname" "$cityname")"
					fi
					printf "\\n"
				else
					exitmenu="exit"
				fi
			fi
		fi
	fi
	
	if [ "$exitmenu" != "exit" ]; then
		GLOBAL_VPN_NO="$vpnnum"
		GLOBAL_VPN_PROVIDER="$vpnprovider"
		GLOBAL_VPN_PROT="$vpnprot"
		GLOBAL_VPN_TYPE="$vpntype"
		GLOBAL_COUNTRY_NAME="$countryname"
		GLOBAL_COUNTRY_ID="$countryid"
		GLOBAL_CITY_NAME="$cityname"
		GLOBAL_CTIY_ID="$cityid"
		return 0
	else
		return 1
	fi
}

SetScheduleParameters(){
	exitmenu=""
	vpnnum=""
	formattype=""
	crudays=""
	crudaysvalidated=""
	cruhours=""
	crumins=""
	
	while true; do
		printf "\\n${BOLD}Please enter the VPN client number (pick from list):${CLEARFORMAT}  "
		read -r vpn_choice
		
		if [ "$vpn_choice" = "e" ]; then
			exitmenu="exit"
			break
		elif ! Validate_Number "$vpn_choice"; then
			printf "\\n\\e[31mPlease enter a valid number (pick from list)${CLEARFORMAT}\\n"
		else
			if [ "$vpn_choice" -lt 1 ] || [ "$vpn_choice" -gt 5 ]; then
				printf "\\n\\e[31mPlease enter a number between 1 and 5${CLEARFORMAT}\\n"
			else
				vpnnum="$vpn_choice"
				printf "\\n"
				break
			fi
		fi
	done
	
	if [ "$exitmenu" != "exit" ]; then
		if [ "$(grep "vpn${vpnnum}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
			Print_Output false "VPN client $vpnnum is not managed, cannot enable schedule" "$ERR"
			return 1
		fi
		while true; do
			printf "\\n${BOLD}Please choose which day(s) to update VPN configuration (0-6, * for every day, or comma separated days):${CLEARFORMAT}  "
			read -r day_choice
			
			if [ "$day_choice" = "e" ]; then
				exitmenu="exit"
				break
			elif [ "$day_choice" = "*" ]; then
				crudays="$day_choice"
				printf "\\n"
				break
			elif [ -z "$day_choice" ]; then
				printf "\\n\\e[31mPlease enter a valid number (0-6) or comma separated values${CLEARFORMAT}\\n"
			else
				crudaystmp="$(echo "$day_choice" | sed "s/,/ /g")"
				crudaysvalidated="true"
				for i in $crudaystmp; do
					if ! Validate_Number "$i"; then
						printf "\\n\\e[31mPlease enter a valid number (0-6) or comma separated values${CLEARFORMAT}\\n"
						crudaysvalidated="false"
						break
					else
						if [ "$i" -lt 0 ] || [ "$i" -gt 6 ]; then
							printf "\\n\\e[31mPlease enter a number between 0 and 6 or comma separated values${CLEARFORMAT}\\n"
							crudaysvalidated="false"
							break
						fi
					fi
				done
				if [ "$crudaysvalidated" = "true" ]; then
					crudays="$day_choice"
					printf "\\n"
					break
				fi
			fi
		done
	fi
	
	if [ "$exitmenu" != "exit" ]; then
		while true; do
			printf "\\n${BOLD}Please choose the format to specify the hour/minute(s) to update VPN configuration:${CLEARFORMAT}\\n"
			printf "    1. Every X hours/minutes\\n"
			printf "    2. Custom\\n\\n"
			printf "Choose an option:  "
			read -r formatmenu
			
			case "$formatmenu" in
				1)
					formattype="everyx"
					printf "\\n"
					break
				;;
				2)
					formattype="custom"
					printf "\\n"
					break
				;;
				e)
					exitmenu="exit"
					break
				;;
				*)
					printf "\\n\\e[31mPlease enter a valid choice (1-2)${CLEARFORMAT}\\n"
				;;
			esac
		done
	fi
	
	if [ "$exitmenu" != "exit" ]; then
		if [ "$formattype" = "everyx" ]; then
			while true; do
				printf "\\n${BOLD}Please choose whether to specify every X hours or every X minutes to update VPN configuration:${CLEARFORMAT}\\n"
				printf "    1. Hours\\n"
				printf "    2. Minutes\\n\\n"
				printf "Choose an option:  "
				read -r formatmenu
				
				case "$formatmenu" in
					1)
						formattype="hours"
						printf "\\n"
						break
					;;
					2)
						formattype="mins"
						printf "\\n"
						break
					;;
					e)
						exitmenu="exit"
						break
					;;
					*)
						printf "\\n\\e[31mPlease enter a valid choice (1-2)${CLEARFORMAT}\\n"
					;;
				esac
			done
		fi
	fi
	
	if [ "$exitmenu" != "exit" ]; then
		if [ "$formattype" = "hours" ]; then
			while true; do
				printf "\\n${BOLD}Please choose how often to update VPN configuration (every X hours, where X is 1-24):${CLEARFORMAT}  "
				read -r hour_choice
				
				if [ "$hour_choice" = "e" ]; then
					exitmenu="exit"
					break
				elif ! Validate_Number "$hour_choice"; then
						printf "\\n\\e[31mPlease enter a valid number (1-24)${CLEARFORMAT}\\n"
				elif [ "$hour_choice" -lt 1 ] || [ "$hour_choice" -gt 24 ]; then
					printf "\\n\\e[31mPlease enter a number between 1 and 24${CLEARFORMAT}\\n"
				else
					if [ "$hour_choice" -eq 24 ]; then
						cruhours=0
						crumins=0
						printf "\\n"
						break
					else
						cruhours="*/$hour_choice"
						crumins=0
						printf "\\n"
						break
					fi
				fi
			done
		elif [ "$formattype" = "mins" ]; then
			while true; do
				printf "\\n${BOLD}Please choose how often to update VPN configuration (every X minutes, where X is 1-30):${CLEARFORMAT}  "
				read -r min_choice
				
				if [ "$min_choice" = "e" ]; then
					exitmenu="exit"
					break
				elif ! Validate_Number "$min_choice"; then
						printf "\\n\\e[31mPlease enter a valid number (1-30)${CLEARFORMAT}\\n"
				elif [ "$min_choice" -lt 1 ] || [ "$min_choice" -gt 30 ]; then
					printf "\\n\\e[31mPlease enter a number between 1 and 30${CLEARFORMAT}\\n"
				else
					crumins="*/$min_choice"
					cruhours="*"
					printf "\\n"
					break
				fi
			done
		fi
	fi
	
	if [ "$exitmenu" != "exit" ]; then
		if [ "$formattype" = "custom" ]; then
			while true; do
				printf "\\n${BOLD}Please choose which hour(s) to update VPN configuration (0-23, * for every hour, or comma separated hours):${CLEARFORMAT}  "
				read -r hour_choice
				
				if [ "$hour_choice" = "e" ]; then
					exitmenu="exit"
					break
				elif [ "$hour_choice" = "*" ]; then
					cruhours="$hour_choice"
					printf "\\n"
					break
				else
					cruhourstmp="$(echo "$hour_choice" | sed "s/,/ /g")"
					cruhoursvalidated="true"
					for i in $cruhourstmp; do
						if ! Validate_Number "$i"; then
							printf "\\n\\e[31mPlease enter a valid number (0-23) or comma separated values${CLEARFORMAT}\\n"
							cruhoursvalidated="false"
							break
						else
							if [ "$i" -lt 0 ] || [ "$i" -gt 23 ]; then
								printf "\\n\\e[31mPlease enter a number between 0 and 23 or comma separated values${CLEARFORMAT}\\n"
								cruhoursvalidated="false"
								break
							fi
						fi
					done
					if [ "$cruhoursvalidated" = "true" ]; then
						cruhours="$hour_choice"
						printf "\\n"
						break
					fi
				fi
			done
		fi
	fi
	
	if [ "$exitmenu" != "exit" ]; then
		if [ "$formattype" = "custom" ]; then
			while true; do
				printf "\\n${BOLD}Please choose which minutes(s) to update VPN configuration (0-59, * for every minute, or comma separated minutes):${CLEARFORMAT}  "
				read -r min_choice
				
				if [ "$min_choice" = "e" ]; then
					exitmenu="exit"
					break
				elif [ "$min_choice" = "*" ]; then
					crumins="$min_choice"
					printf "\\n"
					break
				else
					cruminstmp="$(echo "$min_choice" | sed "s/,/ /g")"
					cruminsvalidated="true"
					for i in $cruminstmp; do
						if ! Validate_Number "$i"; then
							printf "\\n\\e[31mPlease enter a valid number (0-59) or comma separated values${CLEARFORMAT}\\n"
							cruminsvalidated="false"
							break
						else
							if [ "$i" -lt 0 ] || [ "$i" -gt 59 ]; then
								printf "\\n\\e[31mPlease enter a number between 0 and 59 or comma separated values${CLEARFORMAT}\\n"
								cruminsvalidated="false"
								break
							fi
						fi
					done
					if [ "$cruminsvalidated" = "true" ]; then
						crumins="$min_choice"
						printf "\\n"
						break
					fi
				fi
			done
		fi
	fi
	
	if [ "$exitmenu" != "exit" ]; then
		GLOBAL_VPN_NO="$vpnnum"
		GLOBAL_CRU_DAYNUMBERS="$crudays"
		GLOBAL_CRU_HOURS="$cruhours"
		GLOBAL_CRU_MINS="$crumins"
		return 0
	else
		return 1
	fi
}

SetVPNCustomSettings(){
	VPN_NO="$1"
	# Caller globals may describe another slot; always read anchored values here.
	VPN_PROVIDER="$(grep "^vpn${VPN_NO}_provider=" "$SCRIPT_CONF" | cut -f2 -d"=")"
	VPN_PROVIDER_LC="$(printf '%s' "$VPN_PROVIDER" | tr 'A-Z' 'a-z')"
	VPN_PROT_SHORT="$(grep "^vpn${VPN_NO}_protocol=" "$SCRIPT_CONF" | cut -f2 -d"=")"
	case "$VPN_PROT_SHORT" in
		UDP|udp) VPN_PROT_SHORT="UDP" ;;
		TCP|tcp) VPN_PROT_SHORT="TCP" ;;
		*)
			Print_Output true "Cannot determine protocol for VPN client $VPN_NO custom settings" "$ERR"
			return 1
		;;
	esac

	# Signature: slot [family version_number [profile]]. Refreshes pass the
	# operation snapshot; direct menu calls detect afresh. Profile text alone
	# cannot establish whether effective traffic shaping is enabled.
	if [ "$#" -ge 3 ]; then
		OVPN_RUNTIME_FAMILY="$2"
		OVPN_RUNTIME_NUMBER="$3"
	else
		Detect_OpenVPN_Runtime
	fi
	case "$OVPN_RUNTIME_FAMILY" in modern) VPN_CUSTOM_FAMILY="modern" ;; *) VPN_CUSTOM_FAMILY="legacy" ;; esac
	VPN_OVPNVER="$OVPN_RUNTIME_NUMBER"
	VPN_MUTE="$(grep "^vpn${VPN_NO}_mute=" "$SCRIPT_CONF" | cut -f2 -d"=")"
	[ -z "$VPN_MUTE" ] && VPN_MUTE="20"
	VPN_DEBUGVERB="$(grep "^vpn${VPN_NO}_debugverb=" "$SCRIPT_CONF" | cut -f2 -d"=")"

	VPN_CUSTOM_SHARED='remote-random
resolv-retry infinite
remote-cert-tls server
ping-timer-rem
persist-tun
reneg-sec 0
mute-replay-warnings
sndbuf 524288
rcvbuf 524288
pull-filter ignore "auth-token"
pull-filter ignore "ifconfig-ipv6"
pull-filter ignore "route-ipv6"
auth-nocache'
	VPN_CUSTOM_LEGACY_SHARED="$VPN_CUSTOM_SHARED"
	VPN_CUSTOM_MODERN_SHARED="$VPN_CUSTOM_SHARED"
	# persist-key remains functional through 2.6; 2.7 ignores it as redundant.
	if [ -z "$VPN_OVPNVER" ] || ! Validate_Number "$VPN_OVPNVER" || [ "$VPN_OVPNVER" -lt 2007000 ]; then
		VPN_CUSTOM_LEGACY_SHARED="$VPN_CUSTOM_LEGACY_SHARED
persist-key"
		VPN_CUSTOM_MODERN_SHARED="$VPN_CUSTOM_MODERN_SHARED
persist-key"
	fi
	if Validate_Number "$VPN_MUTE" && [ "$VPN_MUTE" -gt 0 ]; then
		VPN_CUSTOM_LEGACY_SHARED="$VPN_CUSTOM_LEGACY_SHARED
mute $VPN_MUTE"
		VPN_CUSTOM_MODERN_SHARED="$VPN_CUSTOM_MODERN_SHARED
mute $VPN_MUTE"
	fi
	if [ "$VPN_DEBUGVERB" = "true" ]; then
		VPN_CUSTOM_LEGACY_SHARED="$VPN_CUSTOM_LEGACY_SHARED
verb 4"
		VPN_CUSTOM_MODERN_SHARED="$VPN_CUSTOM_MODERN_SHARED
verb 4"
	fi

	# Keep six family/protocol lists explicit even where entries are shared.
	VPN_CUSTOM_LEGACY_UDP='explicit-exit-notify 3'
	VPN_CUSTOM_LEGACY_TCP=""
	VPN_CUSTOM_MODERN_UDP='explicit-exit-notify 3'
	VPN_CUSTOM_MODERN_TCP=""
	if [ "$VPN_PROVIDER_LC" = "nordvpn" ]; then
		if [ "$VPN_CUSTOM_FAMILY" = "legacy" ]; then
			VPN_CUSTOM_LEGACY_UDP="$(printf 'tun-mtu 1500\ntun-mtu-extra 32\n%s\nmssfix 1450' "$VPN_CUSTOM_LEGACY_UDP")"
			VPN_CUSTOM_LEGACY_TCP="$(printf 'tun-mtu 1500\ntun-mtu-extra 32')"
		fi
	fi
	# fast-io is supported before 2.7 only for UDP/non-Windows clients, but
	# effective shaper state is unavailable here; omit it rather than infer from
	# profile text that shaping is disabled.
	if [ "$VPN_CUSTOM_FAMILY" = "modern" ]; then
		vpncustomoptions="$VPN_CUSTOM_MODERN_SHARED"
		if [ "$VPN_PROT_SHORT" = "UDP" ]; then
			[ -n "$VPN_CUSTOM_MODERN_UDP" ] && vpncustomoptions="$vpncustomoptions
$VPN_CUSTOM_MODERN_UDP"
		else
			[ -n "$VPN_CUSTOM_MODERN_TCP" ] && vpncustomoptions="$vpncustomoptions
$VPN_CUSTOM_MODERN_TCP"
		fi
	else
		vpncustomoptions="$VPN_CUSTOM_LEGACY_SHARED"
		if [ "$VPN_PROT_SHORT" = "UDP" ]; then
			[ -n "$VPN_CUSTOM_LEGACY_UDP" ] && vpncustomoptions="$vpncustomoptions
$VPN_CUSTOM_LEGACY_UDP"
		else
			[ -n "$VPN_CUSTOM_LEGACY_TCP" ] && vpncustomoptions="$vpncustomoptions
$VPN_CUSTOM_LEGACY_TCP"
		fi
	fi
	Write_VPNCustomOptions "$VPN_NO" "$vpncustomoptions"
}

Write_VPNCustomOptions(){
	if Firmware_Build_Before 386.3; then
		vpncustomoptionsbase64="$(echo "$2" | head -c -1 | openssl base64 -A)"
		
		if [ "$(/bin/uname -m)" = "aarch64" ]; then
			nvram set vpn_client"$1"_cust2="$(echo "$vpncustomoptionsbase64" | cut -c0-255)" || return 1
			nvram set vpn_client"$1"_cust21="$(echo "$vpncustomoptionsbase64" | cut -c256-510)" || return 1
			nvram set vpn_client"$1"_cust22="$(echo "$vpncustomoptionsbase64" | cut -c511-765)" || return 1
		elif [ "$(uname -o)" = "ASUSWRT-Merlin" ]; then
			nvram set vpn_client"$1"_cust2="$vpncustomoptionsbase64" || return 1
		else
			nvram set vpn_client"$1"_custom="$2" || return 1
		fi
		nvram commit || return 1
	else
		printf "%s" "$2" > /jffs/openvpn/vpn_client"$1"_custom3 || return 1
	fi
}

# Toggle_VPN_Custom_Settings slot; enabling writes the preset before setting
# the flag, while disabling preserves the existing options block.
Toggle_VPN_Custom_Settings(){
	_TVCS_SLOT="$1"
	_TVCS_MANAGED="$(grep "^vpn${_TVCS_SLOT}_managed=" "$SCRIPT_CONF" | cut -f2 -d"=")"
	if [ "$_TVCS_MANAGED" != "true" ]; then
		Print_Output false "VPN client $_TVCS_SLOT is not managed, cannot apply custom settings" "$ERR"
		return 1
	fi
	_TVCS_STATE="$(grep "^vpn${_TVCS_SLOT}_customsettings=" "$SCRIPT_CONF" | cut -f2 -d"=")"
	if [ "$_TVCS_STATE" = "true" ]; then
		sed -i 's/^vpn'"$_TVCS_SLOT"'_customsettings=.*$/vpn'"$_TVCS_SLOT"'_customsettings=false/' "$SCRIPT_CONF" || return 1
		Print_Output true "Custom settings disabled for VPN client $_TVCS_SLOT" "$PASS"
		return 0
	fi
	if ! SetVPNCustomSettings "$_TVCS_SLOT"; then
		Print_Output false "Could not write custom settings for VPN client $_TVCS_SLOT; custom settings remain disabled" "$ERR"
		return 1
	fi
	sed -i 's/^vpn'"$_TVCS_SLOT"'_customsettings=.*$/vpn'"$_TVCS_SLOT"'_customsettings=true/' "$SCRIPT_CONF" || return 1
	Print_Output true "Custom settings enabled for VPN client $_TVCS_SLOT" "$PASS"
}

# With custom settings off the user's block is kept, but an imported profile's
# verify-x509-name pins the old server's certificate name and breaks the switch.
Strip_Stale_X509Name(){
	_ssx_pattern='^[[:space:]]*verify-x509-name[[:space:]]'
	if Firmware_Build_Before 386.3; then
		if [ "$(/bin/uname -m)" = "aarch64" ]; then
			_ssx_opts="$(printf '%s' "$(nvram get vpn_client"$1"_cust2)$(nvram get vpn_client"$1"_cust21)$(nvram get vpn_client"$1"_cust22)" | openssl base64 -d -A)"
		elif [ "$(uname -o)" = "ASUSWRT-Merlin" ]; then
			_ssx_opts="$(printf '%s' "$(nvram get vpn_client"$1"_cust2)" | openssl base64 -d -A)"
		else
			_ssx_opts="$(nvram get vpn_client"$1"_custom)"
		fi
		printf '%s\n' "$_ssx_opts" | grep -q "$_ssx_pattern" || return 0
		Write_VPNCustomOptions "$1" "$(printf '%s\n' "$_ssx_opts" | grep -v "$_ssx_pattern")" || return 1
	else
		_ssx_file=/jffs/openvpn/vpn_client"$1"_custom3
		if [ ! -f "$_ssx_file" ] || ! grep -q "$_ssx_pattern" "$_ssx_file"; then
			return 0
		fi
		sed -i "/$_ssx_pattern/d" "$_ssx_file" || return 1
	fi
	Print_Output true "Removed verify-x509-name from VPN client $1 custom configuration - it pinned a previous server's certificate name" "$WARN"
}

PressEnter(){
	while true; do
		printf "Press enter to continue..."
		read -r key
		case "$key" in
			*)
				break
			;;
		esac
	done
	return 0
}

ScriptHeader(){
	clear
	printf "\\n"
	printf "${BOLD}#######################################################${CLEARFORMAT}\\n"
	printf "${BOLD}##                                                   ##${CLEARFORMAT}\\n"
	printf "${BOLD}##   __   __ _ __   _ __   _ __ ___    __ _  _ __    ##${CLEARFORMAT}\\n"
	printf "${BOLD}##   \ \ / /| '_ \ | '_ \ | '_   _ \  / _  || '__|   ##${CLEARFORMAT}\\n"
	printf "${BOLD}##    \ V / | |_) || | | || | | | | || (_| || |      ##${CLEARFORMAT}\\n"
	printf "${BOLD}##     \_/  | .__/ |_| |_||_| |_| |_| \__, ||_|      ##${CLEARFORMAT}\\n"
	printf "${BOLD}##          | |                        __/ |         ##${CLEARFORMAT}\\n"
	printf "${BOLD}##          |_|                       |___/          ##${CLEARFORMAT}\\n"
	printf "${BOLD}##                                                   ##${CLEARFORMAT}\\n"
	printf "${BOLD}##                 %s on %-11s             ##${CLEARFORMAT}\\n" "$SCRIPT_VERSION" "$ROUTER_MODEL"
	if [ -f "$SCRIPT_SOURCE_FILE" ]; then
		printf "${BOLD}##                 from %-29s##${CLEARFORMAT}\\n" "$(cat "$SCRIPT_SOURCE_FILE")"
	fi
	printf "${BOLD}##                                                   ##${CLEARFORMAT}\\n"
	printf "${BOLD}##       https://github.com/h0me5k1n/vpnmgr          ##${CLEARFORMAT}\\n"
	printf "${BOLD}##                                                   ##${CLEARFORMAT}\\n"
	printf "${BOLD}#######################################################${CLEARFORMAT}\\n"
	printf "\\n"
}

MainMenu(){
	printf "WebUI for %s is available at:\\n${SETTING}%s${CLEARFORMAT}\\n\\n" "$SCRIPT_NAME" "$(Get_WebUI_URL)"
	printf "1.    List VPN client configurations\\n"
	printf "1l.   List NordVPN clients with server load percentages\\n\\n"
	printf "2.    Update configuration for a managed VPN client\\n\\n"
	printf "3.    Toggle management for a VPN client\\n\\n"
	printf "4.    Search for new recommended server/reload server\\n\\n"
	printf "5.    Toggle scheduled VPN client update/reload\\n"
	printf "6.    Update schedule for a VPN client\\n\\n"
	printf "7.    Toggle %s custom settings for a VPN client\\n\\n" "$SCRIPT_NAME"
	printf "8.    Configure logging settings for a VPN client\\n\\n"
	printf "r.    Refresh cached data from VPN providers\\n\\n"
	printf "u.    Check for updates\\n"
	printf "uf.   Update %s with latest version (force)\\n\\n" "$SCRIPT_NAME"
	printf "e.    Exit %s\\n\\n" "$SCRIPT_NAME"
	printf "z.    Uninstall %s\\n" "$SCRIPT_NAME"
	printf "\\n"
	printf "${BOLD}###################################################${CLEARFORMAT}\\n"
	printf "\\n"
	
	while true; do
		printf "Choose an option:  "
		read -r menu
		case "$menu" in
			1)
				printf "\\n"
				ScriptHeader
				ListVPNClients false show
				PressEnter
				break
			;;
			1l)
				printf "\\n"
				ScriptHeader
				ListVPNClients true show
				PressEnter
				break
			;;
			2)
				printf "\\n"
				if Check_Lock menu; then
					Menu_UpdateVPN
				fi
				PressEnter
				break
			;;
			3)
				printf "\\n"
				if SetVPNClient show; then
					if [ "$(grep "vpn${GLOBAL_VPN_NO}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
						ManageVPN "$GLOBAL_VPN_NO"
						if [ -z "$(nvram get vpn_client"$GLOBAL_VPN_NO"_addr)" ]; then
							while true; do
								printf "\\n${BOLD}VPN client %s has not been configured yet. Configure it now? (y/n)${CLEARFORMAT}  " "$GLOBAL_VPN_NO"
								read -r confirm
								case "$confirm" in
									y|Y)
										if Check_Lock menu; then
											Menu_UpdateVPN
										fi
										break
									;;
									n|N)
										printf "\\n"
										break
									;;
									*)
										printf "\\n${BOLD}Please enter a valid choice (y/n)${CLEARFORMAT}\\n"
									;;
								esac
							done
						fi
					else
						UnmanageVPN "$GLOBAL_VPN_NO"
					fi
				fi
				PressEnter
				break
			;;
			4)
				printf "\\n"
				if Check_Lock menu; then
					Menu_SearchVPN
				fi
				PressEnter
				break
			;;
			5)
				printf "\\n"
				if SetVPNClient hide; then
					if [ "$(grep "vpn${GLOBAL_VPN_NO}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
						Print_Output false "VPN client $GLOBAL_VPN_NO is not managed, cannot enable schedule" "$ERR"
						break
					fi
					if [ "$(grep "vpn${GLOBAL_VPN_NO}_schenabled" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
						ScheduleVPN "$GLOBAL_VPN_NO"
					else
						CancelScheduleVPN "$GLOBAL_VPN_NO"
					fi
				fi
				PressEnter
				break
			;;
			6)
				printf "\\n"
				Menu_ScheduleVPN
				PressEnter
				break
			;;
			7)
				printf "\\n"
				printf "Please enter VPN client number(s) (e.g. 3, 1-5, or 1,4,2 - 'e' to cancel):  "
				_menu7_cancel="false"
				while true; do
					if ! read -r slot_choice; then
						return 0
					fi
					if [ "$slot_choice" = "e" ] || [ "$slot_choice" = "E" ]; then
						_menu7_cancel="true"
						break
					elif ParseSlotSelection "$slot_choice"; then
						break
					else
						printf "\\n\\e[31mPlease enter a valid slot number, range (1-5), or comma list${CLEARFORMAT}\\n"
						printf "Please enter VPN client number(s) (e.g. 3, 1-5, or 1,4,2 - 'e' to cancel):  "
					fi
				done
				if [ "$_menu7_cancel" = "false" ]; then
					for _menu7_slot in $GLOBAL_VPN_SLOTS; do
						GLOBAL_VPN_NO="$_menu7_slot"
						if [ "$(grep "^vpn${GLOBAL_VPN_NO}_managed=" "$SCRIPT_CONF" | cut -f2 -d"=")" != "true" ]; then
							Print_Output false "VPN client $GLOBAL_VPN_NO is not managed; skipping custom settings" "$WARN"
							continue
						fi
						if ! Toggle_VPN_Custom_Settings "$GLOBAL_VPN_NO"; then
							Print_Output false "VPN client $GLOBAL_VPN_NO custom-settings toggle failed" "$ERR"
						fi
					done
					PressEnter
				fi
				break
			;;
			8)
				printf "\\n"
				if SetVPNClient hide; then
					if [ "$(grep "vpn${GLOBAL_VPN_NO}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
						Print_Output false "VPN client $GLOBAL_VPN_NO is not managed, cannot configure logging settings" "$ERR"
						break
					fi
					while true; do
						printf "\\n${BOLD}Please enter how many repeated identical OpenVPN log lines to collapse into one (0 to disable, default 20):${CLEARFORMAT}  "
						read -r mute_choice
						if Validate_Number "$mute_choice" && [ "$mute_choice" -ge 0 ]; then
							break
						else
							printf "\\n\\e[31mPlease enter a number 0 or greater${CLEARFORMAT}\\n"
						fi
					done
					while true; do
						printf "\\n${BOLD}Enable verbose OpenVPN debug logging (verb 4) for this client? (y/n)${CLEARFORMAT}  "
						read -r debugverb_choice
						case "$debugverb_choice" in
							y|Y)
								debugverb_choice="true"
								break
							;;
							n|N)
								debugverb_choice="false"
								break
							;;
							*)
								printf "\\n\\e[31mPlease enter y or n${CLEARFORMAT}\\n"
							;;
						esac
					done
					sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_mute.*$/vpn'"$GLOBAL_VPN_NO"'_mute='"$mute_choice"'/' "$SCRIPT_CONF" || {
						Print_Output false "Could not save logging settings for VPN client $GLOBAL_VPN_NO" "$ERR"
						break
					}
					sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_debugverb.*$/vpn'"$GLOBAL_VPN_NO"'_debugverb='"$debugverb_choice"'/' "$SCRIPT_CONF" || {
						Print_Output false "Could not save logging settings for VPN client $GLOBAL_VPN_NO" "$ERR"
						break
					}
					if [ "$(grep "vpn${GLOBAL_VPN_NO}_customsettings" "$SCRIPT_CONF" | cut -f2 -d"=")" = "true" ]; then
						if ! SetVPNCustomSettings "$GLOBAL_VPN_NO"; then
							Print_Output false "Could not write custom OpenVPN options for VPN client $GLOBAL_VPN_NO" "$ERR"
							break
						fi
					fi
					Print_Output true "Updated logging settings for VPN client $GLOBAL_VPN_NO" "$PASS"
				fi
				PressEnter
				break
			;;
			r)
				printf "\\n"
				Refresh_Provider_Cache
				PressEnter
				break
			;;
			u)
				printf "\\n"
				if Check_Lock menu; then
					Update_Version
					Clear_Lock
				fi
				PressEnter
				break
			;;
			uf)
				printf "\\n"
				if Check_Lock menu; then
					Update_Version force
					Clear_Lock
				fi
				PressEnter
				break
			;;
			e)
				ScriptHeader
				printf "\\n${BOLD}Thanks for using %s!${CLEARFORMAT}\\n\\n\\n" "$SCRIPT_NAME"
				exit 0
			;;
			z)
				while true; do
					printf "\\n${BOLD}Are you sure you want to uninstall %s? (y/n)${CLEARFORMAT}  " "$SCRIPT_NAME"
					read -r confirm
					case "$confirm" in
						y|Y)
							Menu_Uninstall
							exit 0
						;;
						*)
							break
						;;
					esac
				done
			;;
			*)
				printf "\\nPlease choose a valid option\\n\\n"
			;;
		esac
	done
	
	ScriptHeader
	MainMenu
}

Menu_UpdateVPN(){
	ScriptHeader
	ListVPNClients false hide
	printf "Choose options as follows:\\n"
	printf "    - VPN client (pick from list)\\n"
	printf "    - VPN provider (pick from list)\\n"
	printf "    - type of VPN (pick from list)\\n"
	printf "    - protocol (pick from list)\\n"
	printf "    - country/city of VPN Server (type to search)\\n"
	printf "\\n"
	printf "${BOLD}#########################################################${CLEARFORMAT}\\n"

	while true; do
		printf "\\n${BOLD}Please enter VPN client number(s) (e.g. 3, 1-5, or 1,4,2 - 'e' to exit):${CLEARFORMAT}  "
		read -r slot_choice
		if [ "$slot_choice" = "e" ]; then
			Clear_Lock
			return 1
		elif ParseSlotSelection "$slot_choice"; then
			break
		else
			printf "\\n\\e[31mPlease enter a valid slot number, range (1-5), or comma list${CLEARFORMAT}\\n"
		fi
	done

	MUV_TOTAL=$(printf '%s\n' "$GLOBAL_VPN_SLOTS" | wc -w)
	MUV_IDX=0
	MUV_CONFIGURED=""
	MUV_SKIPPED=""
	MUV_FAILED=""
	MUV_STOPPED=""

	for MUV_SLOT in $GLOBAL_VPN_SLOTS; do
		MUV_IDX=$((MUV_IDX + 1))
		printf "\\n${BOLD}VPN client %s — %s of %s${CLEARFORMAT}\\n" "$MUV_SLOT" "$MUV_IDX" "$MUV_TOTAL"
		if [ "$(grep "vpn${MUV_SLOT}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
			Print_Output false "VPN client $MUV_SLOT is not managed - skipping" "$WARN"
			MUV_SKIPPED="$MUV_SKIPPED $MUV_SLOT"
			continue
		fi
		if SetVPNParameters "$MUV_SLOT"; then
			sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_provider.*$/vpn'"$GLOBAL_VPN_NO"'_provider='"$GLOBAL_VPN_PROVIDER"'/' "$SCRIPT_CONF"
			sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_type.*$/vpn'"$GLOBAL_VPN_NO"'_type='"$GLOBAL_VPN_TYPE"'/' "$SCRIPT_CONF"
			sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_protocol.*$/vpn'"$GLOBAL_VPN_NO"'_protocol='"$GLOBAL_VPN_PROT"'/' "$SCRIPT_CONF"
			sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_countryname.*$/vpn'"$GLOBAL_VPN_NO"'_countryname='"$GLOBAL_COUNTRY_NAME"'/' "$SCRIPT_CONF"
			sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_countryid.*$/vpn'"$GLOBAL_VPN_NO"'_countryid='"$GLOBAL_COUNTRY_ID"'/' "$SCRIPT_CONF"
			sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_cityname.*$/vpn'"$GLOBAL_VPN_NO"'_cityname='"$GLOBAL_CITY_NAME"'/' "$SCRIPT_CONF"
			sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_cityid.*$/vpn'"$GLOBAL_VPN_NO"'_cityid='"$GLOBAL_CTIY_ID"'/' "$SCRIPT_CONF"
			if UpdateVPNConfig "$GLOBAL_VPN_NO"; then
				MUV_CONFIGURED="$MUV_CONFIGURED $MUV_SLOT"
			else
				MUV_FAILED="$MUV_FAILED $MUV_SLOT"
			fi
		else
			# SetVPNParameters returned 1: either the user exited a sub-prompt
			# with 'e', or a provider-level error (e.g. missing country data)
			# aborted the prompt sequence. Either way there's no coherent
			# state to keep going interactively, so stop the batch here.
			MUV_STOPPED="true"
			break
		fi
	done

	if [ "$MUV_TOTAL" -gt 1 ] || [ -n "$MUV_SKIPPED" ] || [ -n "$MUV_FAILED" ] || [ -n "$MUV_STOPPED" ]; then
		printf "\\n${BOLD}Batch summary:${CLEARFORMAT}\\n"
		[ -n "$MUV_CONFIGURED" ] && printf "    Configured:%s\\n" "$MUV_CONFIGURED"
		[ -n "$MUV_SKIPPED" ] && printf "    Skipped (unmanaged):%s\\n" "$MUV_SKIPPED"
		[ -n "$MUV_FAILED" ] && printf "    Failed:%s\\n" "$MUV_FAILED"
		if [ -n "$MUV_STOPPED" ]; then
			MUV_PROCESSED="$MUV_CONFIGURED $MUV_SKIPPED $MUV_FAILED"
			MUV_UNPROCESSED=""
			for MUV_SLOT in $GLOBAL_VPN_SLOTS; do
				case " $MUV_PROCESSED " in
					*" $MUV_SLOT "*) ;;
					*) MUV_UNPROCESSED="$MUV_UNPROCESSED $MUV_SLOT" ;;
				esac
			done
			printf "    Stopped early - unprocessed:%s\\n" "$MUV_UNPROCESSED"
		fi
	fi

	Clear_Lock
}

Menu_SearchVPN(){
	ScriptHeader
	ListVPNClients false hide

	while true; do
		printf "\\n${BOLD}Please enter VPN client number(s) (e.g. 3, 1-5, or 1,4,2 - 'e' to exit):${CLEARFORMAT}  "
		read -r slot_choice
		if [ "$slot_choice" = "e" ]; then
			Clear_Lock
			return 1
		elif ParseSlotSelection "$slot_choice"; then
			break
		else
			printf "\\n\\e[31mPlease enter a valid slot number, range (1-5), or comma list${CLEARFORMAT}\\n"
		fi
	done

	MSV_TOTAL=$(printf '%s\n' "$GLOBAL_VPN_SLOTS" | wc -w)
	MSV_IDX=0
	MSV_UPDATED=""
	MSV_SKIPPED=""
	MSV_FAILED=""

	for MSV_SLOT in $GLOBAL_VPN_SLOTS; do
		MSV_IDX=$((MSV_IDX + 1))
		printf "\\n${BOLD}VPN client %s — %s of %s${CLEARFORMAT}\\n" "$MSV_SLOT" "$MSV_IDX" "$MSV_TOTAL"
		if [ "$(grep "vpn${MSV_SLOT}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
			Print_Output false "VPN client $MSV_SLOT is not managed, cannot search for new server - skipping" "$WARN"
			MSV_SKIPPED="$MSV_SKIPPED $MSV_SLOT"
			continue
		fi
		if UpdateVPNConfig unattended "$MSV_SLOT"; then
			MSV_UPDATED="$MSV_UPDATED $MSV_SLOT"
		else
			MSV_FAILED="$MSV_FAILED $MSV_SLOT"
		fi
	done

	if [ "$MSV_TOTAL" -gt 1 ] || [ -n "$MSV_SKIPPED" ] || [ -n "$MSV_FAILED" ]; then
		printf "\\n${BOLD}Batch summary:${CLEARFORMAT}\\n"
		[ -n "$MSV_UPDATED" ] && printf "    Updated:%s\\n" "$MSV_UPDATED"
		[ -n "$MSV_SKIPPED" ] && printf "    Skipped (unmanaged):%s\\n" "$MSV_SKIPPED"
		[ -n "$MSV_FAILED" ] && printf "    Failed:%s\\n" "$MSV_FAILED"
	fi

	Clear_Lock
}

Menu_ScheduleVPN(){
	ScriptHeader
	ListVPNClients false hide
	printf "Choose options as follows:\\n"
	printf "    - VPN client (pick from list)\\n"
	printf "    - day(s) to update [0-6]\\n"
	printf "    - hour(s) to update [0-23]\\n"
	printf "    - minute(s) to update [0-59]\\n"
	printf "\\n"
	printf "${BOLD}#########################################################${CLEARFORMAT}\\n"
	
	if SetScheduleParameters; then
		sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_schenabled.*$/vpn'"$GLOBAL_VPN_NO"'_schenabled=true/' "$SCRIPT_CONF"
		sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_schdays.*$/vpn'"$GLOBAL_VPN_NO"'_schdays='"$(echo "$GLOBAL_CRU_DAYNUMBERS" | sed 's/0/Sun/;s/1/Mon/;s/2/Tues/;s/3/Wed/;s/4/Thurs/;s/5/Fri/;s/6/Sat/;')"'/' "$SCRIPT_CONF"
		sed -i 's~^vpn'"$GLOBAL_VPN_NO"'_schhours.*$~vpn'"$GLOBAL_VPN_NO"'_schhours='"$GLOBAL_CRU_HOURS"'~' "$SCRIPT_CONF"
		sed -i 's~^vpn'"$GLOBAL_VPN_NO"'_schmins.*$~vpn'"$GLOBAL_VPN_NO"'_schmins='"$GLOBAL_CRU_MINS"'~' "$SCRIPT_CONF"
		ScheduleVPN "$GLOBAL_VPN_NO"
	fi
}

Check_Requirements(){
	CHECKSFAILED="false"
	
	if [ "$(nvram get jffs2_scripts)" -ne 1 ]; then
		nvram set jffs2_scripts=1
		nvram commit
		Print_Output true "Custom JFFS Scripts enabled" "$WARN"
	fi
	
	if [ ! -f /opt/bin/opkg ]; then
		Print_Output false "Entware not detected!" "$ERR"
		CHECKSFAILED="true"
	fi
	
	if ! Firmware_Version_Check ; then
		Print_Output false "Unsupported firmware version detected" "$ERR"
		Print_Output false "$SCRIPT_NAME requires Merlin 384.15/384.13_4 or Fork 43E5 (or later)" "$ERR"
		CHECKSFAILED="true"
	fi
	
	if [ "$CHECKSFAILED" = "false" ]; then
		Print_Output false "Installing required packages from Entware" "$PASS"
		opkg update
		opkg install jq
		opkg install p7zip
		opkg install findutils
		return 0
	else
		return 1
	fi
}

Menu_Install(){
	ScriptHeader
	Print_Output true "Welcome to $SCRIPT_NAME $SCRIPT_VERSION, a script by h0me5k1n and JackYaz"
	sleep 1

	if [ -d "$SCRIPT_DIR/providers" ] && [ ! -f "$SCRIPT_DIR/providers_list" ]; then
		Print_Output false "An installation of jackyaz's vpnmgr was detected." "$WARN"
		Print_Output false "Please uninstall it first before installing this version:" "$WARN"
		Print_Output false "  vpnmgr uninstall" "$WARN"
		Print_Output false "Then re-run the install command from https://github.com/h0me5k1n/vpnmgr" "$WARN"
		Clear_Lock
		exit 1
	fi

	Print_Output false "Checking your router meets the requirements for $SCRIPT_NAME"

	if ! Check_Requirements; then
		Print_Output false "Requirements for $SCRIPT_NAME not met, please see above for the reason(s)" "$CRIT"
		PressEnter
		Clear_Lock
		rm -f "/jffs/scripts/$SCRIPT_NAME" 2>/dev/null
		exit 1
	fi
	
	# Mark this installation as ours before creating the providers directory,
	# so a failed first download can be retried without looking like legacy.
	mkdir -p "$SCRIPT_DIR" || return 1
	[ -f "$SCRIPT_DIR/providers_list" ] || : > "$SCRIPT_DIR/providers_list" || return 1
	Create_Dirs
	Conf_Exists
	Configure_Test_Providers || return 1
	# Main-script provenance is already verified by Bootstrap_Install. Retain it
	# even if a dependency fails; .files_source records successful assets only.
	Record_Install_Source || return 1
	Auto_Cron create 2>/dev/null
	Auto_Startup create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	
	Update_Addon_Files "$SCRIPT_VERSION" || return 1
	Record_Install_Source || return 1
	Refresh_Provider_Cache
	Create_Symlinks || return 1

	Set_Version_Custom_Settings local "$SCRIPT_VERSION"
	Set_Version_Custom_Settings server "$SCRIPT_VERSION"
	Shortcut_Script create
	Clear_Lock

	SCRIPT_UPDATE_READY=false
	ScriptHeader
	MainMenu
}

Menu_Startup(){
	if [ -z "$1" ]; then
		Print_Output true "Missing argument for startup, not starting $SCRIPT_NAME" "$WARN"
		exit 1
	elif [ "$1" != "force" ]; then
		if [ ! -f "$1/entware/bin/opkg" ]; then
			Print_Output true "$1 does not contain Entware, not starting $SCRIPT_NAME" "$WARN"
			exit 1
		else
			Print_Output true "$1 contains Entware, starting $SCRIPT_NAME" "$WARN"
		fi
	fi
	
	NTP_Ready
	
	Check_Lock
	
	if [ "$1" != "force" ]; then
		sleep 25
	fi
	
	Create_Dirs
	Conf_Exists
	Set_Version_Custom_Settings local "$SCRIPT_VERSION"
	Set_Version_Custom_Settings server "$SCRIPT_VERSION"
	Create_Symlinks
	Auto_Cron create 2>/dev/null
	Auto_Startup create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	Shortcut_Script create
	Mount_WebUI
	Clear_Lock
}

Menu_Uninstall(){
	Print_Output true "Removing $SCRIPT_NAME..." "$PASS"
	
	Auto_Cron delete 2>/dev/null
	Auto_Startup delete 2>/dev/null
	Auto_ServiceEvent delete 2>/dev/null
	
	# Per-client schedules are separate cron jobs and services-start lines
	for i in 1 2 3 4 5; do
		if cru l | grep -q "${SCRIPT_NAME}_VPN${i}" || { [ -f /jffs/scripts/services-start ] && grep -q "${SCRIPT_NAME}_VPN${i}" /jffs/scripts/services-start; }; then
			CancelScheduleVPN "$i"
		fi
	done
	
	LOCKFILE=/tmp/addonwebui.lock
	FD=386
	eval exec "$FD>$LOCKFILE"
	flock -x "$FD"
	Get_WebUI_Page "$SCRIPT_DIR/vpnmgr_www.asp"
	if [ -n "$MyPage" ] && [ "$MyPage" != "none" ] && [ -f /tmp/menuTree.js ]; then
		sed -i "\\~$MyPage~d" /tmp/menuTree.js
		umount /www/require/modules/menuTree.js
		mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
		rm -f "$SCRIPT_WEBPAGE_DIR/$MyPage"
		rm -f "$SCRIPT_WEBPAGE_DIR/$(echo $MyPage | cut -f1 -d'.').title"
	fi
	flock -u "$FD"
	rm -f "$SCRIPT_DIR/vpnmgr_www.asp" 2>/dev/null
	rm -f "$SCRIPT_DIR/vpnmgr_www.js" 2>/dev/null
	
	SETTINGSFILE="/jffs/addons/custom_settings.txt"
	sed -i '/vpnmgr_version_local/d' "$SETTINGSFILE"
	sed -i '/vpnmgr_version_server/d' "$SETTINGSFILE"
	sed -i '/vpnmgr_version_source/d' "$SETTINGSFILE"
	
	rm -rf "$SCRIPT_WEB_DIR" 2>/dev/null
	rm -rf "$SCRIPT_DIR" 2>/dev/null
	
	Shortcut_Script delete
	
	rm -f "/jffs/scripts/$SCRIPT_NAME" 2>/dev/null
	Clear_Lock
	Print_Output true "Uninstall completed" "$PASS"
}

NTP_Ready(){
	if [ "$(nvram get ntp_ready)" -eq 0 ]; then
		ntpwaitcount=0
		while [ "$(nvram get ntp_ready)" -eq 0 ] && [ "$ntpwaitcount" -lt 600 ]; do
			ntpwaitcount="$((ntpwaitcount + 30))"
			Print_Output true "Waiting for NTP to sync..." "$WARN"
			sleep 30
		done
		if [ "$ntpwaitcount" -ge 600 ]; then
			Print_Output true "NTP failed to sync after 10 minutes. Please resolve!" "$CRIT"
			Clear_Lock
			exit 1
		else
			Print_Output true "NTP synced, $SCRIPT_NAME will now continue" "$PASS"
			Clear_Lock
		fi
	fi
}

### function based on @Adamm00's Skynet USB wait function ###
Entware_Ready(){
	if [ ! -f /opt/bin/opkg ]; then
		Check_Lock
		sleepcount=1
		while [ ! -f /opt/bin/opkg ] && [ "$sleepcount" -le 10 ]; do
			Print_Output true "Entware not found, sleeping for 10s (attempt $sleepcount of 10)" "$ERR"
			sleepcount="$((sleepcount + 1))"
			sleep 10
		done
		if [ ! -f /opt/bin/opkg ]; then
			Print_Output true "Entware not found and is required for $SCRIPT_NAME to run, please resolve" "$CRIT"
			Clear_Lock
			exit 1
		else
			Print_Output true "Entware found, $SCRIPT_NAME will now continue" "$PASS"
			Clear_Lock
		fi
	fi
}
### ###

Show_About(){
	cat <<EOF
About
  $SCRIPT_NAME enables easy management of your VPN Client connections for
various VPN providers on AsusWRT-Merlin. Provider-specific logic is
implemented in modular provider scripts under $PROVIDERS_DIR.
The following VPN Providers are supported: NordVPN, Private Internet
Access (PIA, unmaintained) and WeVPN (deprecated).
VPN clients can be configured to automatically refresh on a scheduled
basis using the recommended server from each provider's API.
License
  $SCRIPT_NAME is free to use under the GNU General Public License
  version 3 (GPL-3.0) https://opensource.org/licenses/GPL-3.0
Help & Support
  https://www.snbforums.com/forums/asuswrt-merlin-addons.60/?prefix_id=11
Source code
  https://github.com/h0me5k1n/$SCRIPT_NAME
EOF
	printf "\\n"
}
### ###

### function based on @dave14305's FlexQoS show_help function ###
Show_Help(){
	cat <<EOF
Available commands:
  $SCRIPT_NAME about              explains functionality
  $SCRIPT_NAME update             checks for updates
  $SCRIPT_NAME forceupdate        updates to latest version (force update)
  $SCRIPT_NAME startup force      runs startup actions such as mount WebUI tab
  $SCRIPT_NAME install            installs script
  $SCRIPT_NAME uninstall          uninstalls script
  $SCRIPT_NAME updatevpn X        refresh VPN Client X with the latest server (NordVPN) and settings
  $SCRIPT_NAME refreshcacheddata  triggers a redownload of ovpn file archives from PIA and WeVPN
  $SCRIPT_NAME ntpredirect        apply firewall rules to intercept and redirect NTP traffic
  $SCRIPT_NAME develop            switch to development branch
  $SCRIPT_NAME stable             switch to stable branch
EOF
	printf "\\n"
}
### ###

if [ -z "$1" ]; then
	NTP_Ready
	Entware_Ready
	if [ ! -f /opt/bin/7za ]; then
		opkg update
		opkg install p7zip
	fi
	Create_Dirs
	Conf_Exists
	Auto_Cron create 2>/dev/null
	Auto_Startup create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	Shortcut_Script create
	Sync_Addon_Files || exit 1
	Refresh_Provider_Cache

	Create_Symlinks || exit 1
	ScriptHeader
	MainMenu
	exit 0
fi

case "$1" in
	install)
		Select_Install_Source || exit 1
		Bootstrap_Install || exit 1
		Check_Lock
		Menu_Install
		_install_rc=$?
		Clear_Lock
		exit "$_install_rc"
	;;
	updatevpn)
		NTP_Ready
		Entware_Ready
		UpdateVPNConfig unattended "$2"
		exit $?
	;;
	refreshcacheddata)
		NTP_Ready
		Entware_Ready
		Refresh_Provider_Cache
		exit 0
	;;
	startup)
		Menu_Startup "$2"
		exit 0
	;;
	service_event)
		if [ "$2" = start ]; then
			case "$3" in
				"${SCRIPT_NAME}runtime_"*) Runtime_Detect "${3#${SCRIPT_NAME}runtime_}"; exit $? ;;
				"${SCRIPT_NAME}prepare_"*) Runtime_Prepare "${3#${SCRIPT_NAME}prepare_}"; exit $? ;;
				"${SCRIPT_NAME}recover_"*) Runtime_Recover "${3#${SCRIPT_NAME}recover_}"; exit $? ;;
				"${SCRIPT_NAME}apply_"*) Runtime_Apply "${3#${SCRIPT_NAME}apply_}"; exit $? ;;
			esac
		fi
		if [ "$2" = "start" ] && [ "$3" = "$SCRIPT_NAME" ]; then
			Conf_FromSettings
			for i in 1 2 3 4 5; do
				if [ "$(grep "vpn${i}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "true" ]; then
					ManageVPN "$i"
					if [ "$(grep "vpn${i}_schenabled" "$SCRIPT_CONF" | cut -f2 -d"=")" = "true" ]; then
						ScheduleVPN "$i"
					elif [ "$(grep "vpn${i}_schenabled" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
						CancelScheduleVPN "$i"
					fi
					UpdateVPNConfig unattended "$i"
				elif [ "$(grep "vpn${i}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
					UnmanageVPN "$i"
				fi
			done
			exit 0
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME}refreshcacheddata" ]; then
			rm -f /tmp/detect_vpnmgr.js
			Check_Lock webui
			sleep 3
			echo 'var refreshcacheddatastatus = "InProgress";' > /tmp/detect_vpnmgr.js
			sleep 1
			Refresh_Provider_Cache
			sleep 1
			echo 'var refreshcacheddatastatus = "Done";' > /tmp/detect_vpnmgr.js
			Clear_Lock
			exit 0
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME}getserverload" ]; then
			rm -f /tmp/vpnmgrserverloads
			for i in 1 2 3 4 5; do
				VPN_CLIENTDESC="$(nvram get vpn_client"$i"_desc)"
				[ -z "$VPN_CLIENTDESC" ] && continue
				VPN_PROV_LC="$(grep "vpn${i}_provider" "$SCRIPT_CONF" | cut -f2 -d"=" | tr 'A-Z' 'a-z')"
				if Load_Provider "$VPN_PROV_LC" 2>/dev/null; then
					printf "var vpn%s_serverload=%s;\\r\\n" "$i" "$("provider_${VPN_PROV_LC}_get_server_load" "$VPN_CLIENTDESC")" >> /tmp/vpnmgrserverloads.tmp
				fi
			done
			mv /tmp/vpnmgrserverloads.tmp /tmp/vpnmgrserverloads
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME}checkupdate" ]; then
			Update_Check
			exit $?
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME}doupdate" ]; then
			Update_Version force unattended
			exit $?
		fi
		exit 0
	;;
	update)
		Update_Version
		exit $?
	;;
	forceupdate)
		Update_Version force
		exit $?
	;;
	setversion)
		Resolve_Installed_Source || exit 1
		Set_Version_Custom_Settings local "$SCRIPT_VERSION"
		Set_Version_Custom_Settings server "$SCRIPT_VERSION"
		if [ ! -f /opt/bin/7za ]; then
			opkg update
			opkg install p7zip
		fi
		Create_Dirs
		Conf_Exists
		Auto_Cron create 2>/dev/null
		Auto_Startup create 2>/dev/null
		Auto_ServiceEvent create 2>/dev/null
		Shortcut_Script create
		Sync_Addon_Files || exit 1
		Refresh_Provider_Cache
		Create_Symlinks || exit 1
		exit 0
	;;
	postupdate)
		Resolve_Installed_Source || exit 1
		if [ ! -f /opt/bin/7za ]; then
			opkg update
			opkg install p7zip
		fi
		Create_Dirs
		Conf_Exists
		Auto_Cron create 2>/dev/null
		Auto_Startup create 2>/dev/null
		Auto_ServiceEvent create 2>/dev/null
		Shortcut_Script create
		Sync_Addon_Files || exit 1
		Refresh_Provider_Cache
		Create_Symlinks || exit 1
		exit 0
	;;
	about)
		ScriptHeader
		Show_About
		exit 0
	;;
	help)
		ScriptHeader
		Show_Help
		exit 0
	;;
	develop)
		SCRIPT_BRANCH="develop"
		Update_Version force "" "$SCRIPT_BRANCH"
		exit $?
	;;
	stable)
		SCRIPT_BRANCH="main"
		Update_Version force "" "$SCRIPT_BRANCH"
		exit $?
	;;
	uninstall)
		Menu_Uninstall
		exit 0
	;;
	*)
		ScriptHeader
		Print_Output false "Command not recognised." "$ERR"
		Print_Output false "For a list of available commands run: $SCRIPT_NAME help"
		exit 1
	;;
esac
