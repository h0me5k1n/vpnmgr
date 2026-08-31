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
readonly SCRIPT_VERSION="v3.2.0"
SCRIPT_BRANCH="main"
SCRIPT_REPO="https://raw.githubusercontent.com/h0me5k1n/$SCRIPT_NAME/$SCRIPT_BRANCH"
readonly SCRIPT_DIR="/jffs/addons/$SCRIPT_NAME.d"
readonly SCRIPT_CONF="$SCRIPT_DIR/config"
readonly OVPN_ARCHIVE_DIR="$SCRIPT_DIR/ovpn"
readonly PROVIDERS_DIR="$SCRIPT_DIR/providers"
readonly SCRIPT_WEBPAGE_DIR="$(readlink /www/user)"
readonly SCRIPT_WEB_DIR="$SCRIPT_WEBPAGE_DIR/$SCRIPT_NAME"
readonly SCRIPT_WWW_DIR="$SCRIPT_DIR/www"
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

OpenVPN_Version_Number(){
	# Echoes the router's OpenVPN version as a zero-padded integer for numeric
	# comparison (e.g. 2007000 for 2.7.0). Empty if openvpn is missing or unparseable.
	openvpn --version 2>/dev/null | awk 'NR==1 && $1=="OpenVPN" {
		n=split($2,v,"."); printf("%d%03d%03d\n", v[1], v[2], (n>2?v[3]:0)); exit }'
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
		trap 'Clear_Lock' INT TERM
		return 0
	fi
}

Clear_Lock(){
	rm -f "/tmp/$SCRIPT_NAME.lock" 2>/dev/null
	return 0
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

Update_Check(){
	echo 'var updatestatus = "InProgress";' > "$SCRIPT_WEB_DIR/detect_update.js"
	doupdate="false"
	localver=$(grep "SCRIPT_VERSION=" "/jffs/scripts/$SCRIPT_NAME" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
	/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | grep -qF "h0me5k1n" || { Print_Output true "404 error detected - stopping update" "$ERR"; return 1; }
	serverver=$(/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | grep "SCRIPT_VERSION=" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
	if [ "$localver" != "$serverver" ]; then
		doupdate="version"
		Set_Version_Custom_Settings server "$serverver"
		echo 'var updatestatus = "'"$serverver"'";'  > "$SCRIPT_WEB_DIR/detect_update.js"
	else
		localmd5="$(md5sum "/jffs/scripts/$SCRIPT_NAME" | awk '{print $1}')"
		remotemd5="$(curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | md5sum | awk '{print $1}')"
		if [ "$localmd5" != "$remotemd5" ]; then
			doupdate="md5"
			Set_Version_Custom_Settings server "$serverver-hotfix"
			echo 'var updatestatus = "'"$serverver-hotfix"'";'  > "$SCRIPT_WEB_DIR/detect_update.js"
		fi
	fi
	if [ "$doupdate" = "false" ]; then
		echo 'var updatestatus = "None";'  > "$SCRIPT_WEB_DIR/detect_update.js"
	fi
	echo "$doupdate,$localver,$serverver"
}

Update_Version(){
	if [ -z "$1" ]; then
		updatecheckresult="$(Update_Check)"
		isupdate="$(echo "$updatecheckresult" | cut -f1 -d',')"
		localver="$(echo "$updatecheckresult" | cut -f2 -d',')"
		serverver="$(echo "$updatecheckresult" | cut -f3 -d',')"
		
		if [ "$isupdate" = "version" ]; then
			Print_Output true "New version of $SCRIPT_NAME available - $serverver" "$PASS"
		elif [ "$isupdate" = "md5" ]; then
			Print_Output true "MD5 hash of $SCRIPT_NAME does not match - hotfix available $serverver" "$PASS"
		fi
		
		if [ "$isupdate" != "false" ]; then
			printf "\\n${BOLD}Do you want to continue with the update? (y/n)${CLEARFORMAT}  "
			read -r confirm
			case "$confirm" in
				y|Y)
					Update_File web-assets
					Update_File vpnmgr_www.asp
					printf "\\n"
					/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" -o "/jffs/scripts/$SCRIPT_NAME" && Print_Output true "$SCRIPT_NAME successfully updated"
					chmod 0755 "/jffs/scripts/$SCRIPT_NAME"
					Set_Version_Custom_Settings local "$serverver"
					Set_Version_Custom_Settings server "$serverver"
					Clear_Lock
					PressEnter
					exec "$0"
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
		serverver=$(/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | grep "SCRIPT_VERSION=" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
		Print_Output true "Downloading latest version ($serverver) of $SCRIPT_NAME" "$PASS"
		Update_File web-assets
		Update_File vpnmgr_www.asp
		/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" -o "/jffs/scripts/$SCRIPT_NAME" && Print_Output true "$SCRIPT_NAME successfully updated"
		chmod 0755 "/jffs/scripts/$SCRIPT_NAME"
		Set_Version_Custom_Settings local "$serverver"
		Set_Version_Custom_Settings server "$serverver"
		Clear_Lock
		if [ -z "$2" ]; then
			PressEnter
			exec "$0"
		elif [ "$2" = "unattended" ]; then
			exec "$0" postupdate
		fi
		exit 0
	fi
}

Update_File(){
	if [ "$1" = "web-assets" ]; then
		Download_File "$SCRIPT_REPO/www/jquery.js" "$SCRIPT_WWW_DIR/jquery.js"
		Download_File "$SCRIPT_REPO/www/detect.js" "$SCRIPT_WWW_DIR/detect.js"
		Print_Output true "Web assets updated" "$PASS"
	elif [ "$1" = "vpnmgr_www.asp" ]; then
		tmpfile="/tmp/$1"
		Download_File "$SCRIPT_REPO/$1" "$tmpfile"
		if ! diff -q "$tmpfile" "$SCRIPT_DIR/$1" >/dev/null 2>&1; then
			if [ -f "$SCRIPT_DIR/$1" ]; then
				Get_WebUI_Page "$SCRIPT_DIR/$1"
				sed -i "\\~$MyPage~d" /tmp/menuTree.js
				rm -f "$SCRIPT_WEBPAGE_DIR/$MyPage" 2>/dev/null
			fi
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1"
			Print_Output true "New version of $1 downloaded" "$PASS"
			Mount_WebUI
		fi
		rm -f "$tmpfile"
	elif [ "$1" = "vpnmgr_www.js" ]; then
		tmpfile="/tmp/$1"
		Download_File "$SCRIPT_REPO/$1" "$tmpfile"
		if ! diff -q "$tmpfile" "$SCRIPT_DIR/$1" >/dev/null 2>&1; then
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1"
			cp -f "$SCRIPT_DIR/$1" "$SCRIPT_WEB_DIR/$1"
			Print_Output true "New version of $1 downloaded" "$PASS"
		fi
		rm -f "$tmpfile"
	else
		return 1
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

	urlpage="$(sed -nE "/$SCRIPT_NAME/ s/.*url\: \"(user[0-9]+\.asp)\".*/\1/p" /tmp/menuTree.js)"
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
		if [ "$_pstatus" = "ACTIVE" ]; then
			printf '%s|%s\n' "$_pid" "$_pname" >> "$SCRIPT_DIR/providers_list"
			ln -s "$SCRIPT_DIR/${_pid}_countrydata" "$SCRIPT_WEB_DIR/${_pid}_countrydata.htm" 2>/dev/null
		fi
	done
	ln -s "$SCRIPT_DIR/providers_list" "$SCRIPT_WEB_DIR/providers.htm" 2>/dev/null

	cp -f "$SCRIPT_DIR/vpnmgr_www.js" "$SCRIPT_WEB_DIR/vpnmgr_www.js" 2>/dev/null

	ln -s /tmp/detect_vpnmgr.js "$SCRIPT_WEB_DIR/detect_vpnmgr.js" 2>/dev/null
	ln -s /tmp/vpnmgrserverloads "$SCRIPT_WEB_DIR/vpnmgrserverloads.js" 2>/dev/null

	if [ ! -d "$SCRIPT_WEB_DIR/www" ]; then
		ln -s "$SCRIPT_WWW_DIR" "$SCRIPT_WEB_DIR/www" 2>/dev/null
	fi
}

Install_Providers(){
	mkdir -p "$PROVIDERS_DIR"
	# shellcheck disable=SC2043
	for provider in nordvpn; do
		/usr/sbin/curl -fsL --retry 3 \
			"$SCRIPT_REPO/providers/provider_${provider}.sh" \
			-o "$PROVIDERS_DIR/provider_${provider}.sh"
		chmod 0755 "$PROVIDERS_DIR/provider_${provider}.sh"
	done
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

UpdateVPNConfig(){
	ISUNATTENDED=""
	if [ "$1" = "unattended" ]; then
		ISUNATTENDED="true"
		shift
	fi
	VPN_NO="$1"
	VPN_PROVIDER="$(grep "vpn${VPN_NO}_provider" "$SCRIPT_CONF" | cut -f2 -d"=")"
	VPN_PROVIDER_LC="$(printf '%s' "$VPN_PROVIDER" | tr 'A-Z' 'a-z')"
	VPN_PROT_SHORT="$(grep "vpn${VPN_NO}_protocol" "$SCRIPT_CONF" | cut -f2 -d"=")"
	VPN_TYPE_SHORT="$(grep "vpn${VPN_NO}_type" "$SCRIPT_CONF" | cut -f2 -d"=")"
	VPN_COUNTRYID="$(grep "vpn${VPN_NO}_countryid" "$SCRIPT_CONF" | cut -f2 -d"=")"
	VPN_COUNTRYNAME="$(grep "vpn${VPN_NO}_countryname" "$SCRIPT_CONF" | cut -f2 -d"=")"
	VPN_CITYID="$(grep "vpn${VPN_NO}_cityid" "$SCRIPT_CONF" | cut -f2 -d"=")"
	VPN_CITYNAME="$(grep "vpn${VPN_NO}_cityname" "$SCRIPT_CONF" | cut -f2 -d"=")"
	OVPN_ADDR=""

	Load_Provider "$VPN_PROVIDER_LC" || return 1

	Print_Output true "Retrieving VPN server for $VPN_PROVIDER (Protocol: $VPN_PROT_SHORT, Type: $VPN_TYPE_SHORT)"

	OVPN_HOSTNAME="$("provider_${VPN_PROVIDER_LC}_get_server" \
		"$VPN_COUNTRYID" "$VPN_COUNTRYNAME" \
		"$VPN_CITYID" "$VPN_CITYNAME" \
		"$VPN_PROT_SHORT" "$VPN_TYPE_SHORT")"
	[ -z "$OVPN_HOSTNAME" ] && Print_Output true "Could not determine server identifier for VPN client $VPN_NO" "$ERR" && return 1

	OVPN_DETAIL="$("provider_${VPN_PROVIDER_LC}_get_ovpn" "$OVPN_HOSTNAME" "$VPN_PROT_SHORT" "$VPN_TYPE_SHORT")"
	[ -z "$OVPN_DETAIL" ] && Print_Output true "Error retrieving VPN server ovpn file" "$ERR" && return 1

	OVPN_ADDR="$(getIP "$OVPN_DETAIL")"
	[ -z "$OVPN_ADDR" ] && Print_Output true "Could not determine address for VPN server" "$ERR" && return 1
	OVPN_PORT="$(getPort "$OVPN_DETAIL")"
	[ -z "$OVPN_PORT" ] && Print_Output true "Error determining port for VPN server" "$ERR" && return 1
	OVPN_CIPHER="$(getCipher "$OVPN_DETAIL")"
	[ -z "$OVPN_CIPHER" ] && Print_Output true "Error determining cipher for VPN server" "$ERR" && return 1
	OVPN_AUTHDIGEST="$(getAuthDigest "$OVPN_DETAIL")"
	[ -z "$OVPN_AUTHDIGEST" ] && Print_Output true "Error determining auth digest for VPN server" "$ERR" && return 1
	CLIENT_CA="$(getClientCA "$OVPN_DETAIL")"
	[ -z "$CLIENT_CA" ] && Print_Output true "Error determing VPN server Certificate Authority certificate" "$ERR" && return 1

	OVPN_HOSTNAME_SHORT="$("provider_${VPN_PROVIDER_LC}_get_short_name" "$OVPN_HOSTNAME" "$OVPN_ADDR")"

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
		nvram set vpn_client"$VPN_NO"_adns=3
		nvram set vpn_client"$VPN_NO"_enforce=1
		if [ "$(Firmware_Number_Check "$(nvram get buildno)")" -lt "$(Firmware_Number_Check 384.18)" ]; then
			nvram set vpn_client"$VPN_NO"_clientlist="<DummyVPN>172.16.14.1>0.0.0.0>VPN"
		elif [ "$(Firmware_Number_Check "$(nvram get buildno)")" -lt "$(Firmware_Number_Check 386.3)" ]; then
			nvram set vpn_client"$VPN_NO"_clientlist="<DummyVPN>172.16.14.1>>VPN"
		fi
		if ! nvram get vpn_clientx_eas | grep -q "$VPN_NO"; then
			nvram set vpn_clientx_eas="$(nvram get vpn_clientx_eas),$VPN_NO"
		fi
	fi

	nvram set vpn_client"$VPN_NO"_addr="$OVPN_ADDR"
	nvram set vpn_client"$VPN_NO"_port="$OVPN_PORT"
	if [ "$VPN_PROT_SHORT" = "TCP" ]; then
		nvram set vpn_client"$VPN_NO"_proto="tcp-client"
	elif [ "$VPN_PROT_SHORT" = "UDP" ]; then
		nvram set vpn_client"$VPN_NO"_proto="udp"
	fi
	nvram set vpn_client"$VPN_NO"_desc="$VPN_PROVIDER $OVPN_HOSTNAME_SHORT $VPN_TYPE_SHORT $VPN_PROT_SHORT"

	nvram set vpn_client"$VPN_NO"_cipher="$OVPN_CIPHER"
	nvram set vpn_client"$VPN_NO"_crypt="tls"
	nvram set vpn_client"$VPN_NO"_digest="$OVPN_AUTHDIGEST"
	nvram set vpn_client"$VPN_NO"_fw=1
	nvram set vpn_client"$VPN_NO"_if="tun"
	nvram set vpn_client"$VPN_NO"_nat=1
	nvram set vpn_client"$VPN_NO"_ncp_ciphers="AES-256-GCM:AES-128-GCM:AES-256-CBC:AES-128-CBC"
	nvram set vpn_client"$VPN_NO"_ncp_enable=1
	nvram set vpn_client"$VPN_NO"_reneg=0
	nvram set vpn_client"$VPN_NO"_tlsremote=0
	nvram set vpn_client"$VPN_NO"_userauth=1
	nvram set vpn_client"$VPN_NO"_useronly=1

	VPN_COMP="$("provider_${VPN_PROVIDER_LC}_get_comp")"
	nvram set vpn_client"$VPN_NO"_comp="$VPN_COMP"

	VPN_HMAC="$("provider_${VPN_PROVIDER_LC}_get_hmac")"
	nvram set vpn_client"$VPN_NO"_hmac="$VPN_HMAC"

	if [ "$(Firmware_Number_Check "$(nvram get buildno)")" -lt "$(Firmware_Number_Check 384.19)" ]; then
		nvram set vpn_client"$VPN_NO"_connretry="-1"
	else
		nvram set vpn_client"$VPN_NO"_connretry=0
	fi

	if [ "$(grep "vpn${VPN_NO}_customsettings" "$SCRIPT_CONF" | cut -f2 -d"=")" = "true" ]; then
		SetVPNCustomSettings "$VPN_NO"
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
						nvram set vpn_client"$VPN_NO"_username="$vpnusn"
						printf "\\n"
						printf "Please enter password:  "
						read -r vpnpwd
						nvram set vpn_client"$VPN_NO"_password="$vpnpwd"
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
			nvram set vpn_client"$VPN_NO"_username="$vpnusn"
			printf "\\n"
		fi

		if [ -z "$(nvram get vpn_client"$VPN_NO"_password)" ]; then
			printf "\\n${BOLD}No password set for VPN client %s${CLEARFORMAT}\\n" "$VPN_NO"
			printf "Please enter password:  "
			read -r vpnpwd
			nvram set vpn_client"$VPN_NO"_password="$vpnpwd"
			printf "\\n"
		fi
	fi

	nvram commit

	"provider_${VPN_PROVIDER_LC}_write_certs" "$VPN_NO" "$OVPN_DETAIL" || return 1

	retry="false"

	if nvram get vpn_clientx_eas | grep -q "$VPN_NO"; then
		RestartVPNClient "$VPN_NO"

		Print_Output true "Testing that VPN client $VPN_NO is up with a 10s ping test to 1.1.1.1 ($OVPN_HOSTNAME_SHORT $VPN_TYPE_SHORT $VPN_PROT_SHORT)"
		tunnelup="false"
		for i in 1 2 3; do
			if ping -w 10 -I "tun1$VPN_NO" 1.1.1.1 >/dev/null 2>&1; then
				tunnelup="true"
				break
			else
				RestartVPNClient "$VPN_NO"
			fi
		done

		if [ "$tunnelup" = "false" ]; then
			Print_Output true "VPN client $VPN_NO did not come up after 3 attempts, please investigate! ($OVPN_HOSTNAME_SHORT $VPN_TYPE_SHORT $VPN_PROT_SHORT)" "$CRIT"
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
		fi
	fi
	if [ "$retry" = "false" ]; then
		Print_Output true "VPN client $VPN_NO updated ($OVPN_HOSTNAME_SHORT $VPN_TYPE_SHORT $VPN_PROT_SHORT)" "$PASS"
	else
		UpdateVPNConfig "$VPN_NO"
	fi
}

RestartVPNClient(){
	Print_Output true "Restarting VPN client $1"
	service stop_vpnclient"$1" >/dev/null 2>&1
	sleep 5
	if [ ! -f /opt/bin/xargs ]; then
		Print_Output true "Installing findutils from Entware"
		opkg update
		opkg install findutils
	fi
	ps | grep -v grep | grep -i "openvpn" | grep "client$1" | awk '{print $1}' | xargs kill -9 >/dev/null 2>&1
	service start_vpnclient"$1" >/dev/null 2>&1
	sleep 5
}

ManageVPN(){
	VPN_NO="$1"
	
	if [ -z "$(nvram get vpn_client"$VPN_NO"_username)" ] && [ -z "$(nvram get vpn_client"$VPN_NO"_password)" ]; then
		Print_Output false "No credentials set for VPN client $VPN_NO yet - they will be required when you configure it" "$WARN"
	fi

	Print_Output true "Enabling management of VPN client $VPN_NO"
	sed -i 's/^vpn'"$VPN_NO"'_managed.*$/vpn'"$VPN_NO"'_managed=true/' "$SCRIPT_CONF"
	Print_Output true "Management of VPN client $VPN_NO successfully enabled" "$PASS"
}

UnmanageVPN(){
	VPN_NO="$1"
	
	Print_Output true "Removing management of VPN client $VPN_NO"
	sed -i 's/^vpn'"$VPN_NO"'_managed.*$/vpn'"$VPN_NO"'_managed=false/' "$SCRIPT_CONF"
	CancelScheduleVPN "$VPN_NO"
	Print_Output true "Management of VPN client $VPN_NO successfully removed" "$PASS"
}

ScheduleVPN(){
	VPN_NO="$1"
	CRU_DAYNUMBERS="$(grep "vpn${VPN_NO}_schdays" "$SCRIPT_CONF" | cut -f2 -d"=" | sed 's/Sun/0/;s/Mon/1/;s/Tues/2/;s/Wed/3/;s/Thurs/4/;s/Fri/5/;s/Sat/6/;')"
	CRU_HOURS="$(grep "vpn${VPN_NO}_schhours" "$SCRIPT_CONF" | cut -f2 -d"=")"
	CRU_MINUTES="$(grep "vpn${VPN_NO}_schmins" "$SCRIPT_CONF" | cut -f2 -d"=")"
	
	Print_Output true "Configuring scheduled update for VPN client $VPN_NO"
	
	if cru l | grep -q "${SCRIPT_NAME}${VPN_NO}"; then
		cru d "${SCRIPT_NAME}_VPN${VPN_NO}"
	fi
	
	cru a "${SCRIPT_NAME}_VPN${VPN_NO}" "$CRU_MINUTES $CRU_HOURS * * $CRU_DAYNUMBERS /jffs/scripts/$SCRIPT_NAME updatevpn $VPN_NO"
	
	if [ -f /jffs/scripts/services-start ]; then
		sed -i "/${SCRIPT_NAME}_VPN${VPN_NO}/d" /jffs/scripts/services-start
		echo "cru a ${SCRIPT_NAME}_VPN${VPN_NO} \"$CRU_MINUTES $CRU_HOURS * * $CRU_DAYNUMBERS /jffs/scripts/$SCRIPT_NAME updatevpn $VPN_NO\" # $SCRIPT_NAME" >> /jffs/scripts/services-start
	else
		echo "#!/bin/sh" > /jffs/scripts/services-start
		echo "cru a ${SCRIPT_NAME}_VPN${VPN_NO} \"$CRU_MINUTES $CRU_HOURS * * $CRU_DAYNUMBERS /jffs/scripts/$SCRIPT_NAME updatevpn $VPN_NO\" # $SCRIPT_NAME" >> /jffs/scripts/services-start
		chmod 755 /jffs/scripts/services-start
	fi
	
	sed -i 's/^vpn'"$VPN_NO"'_schenabled.*$/vpn'"$VPN_NO"'_schenabled=true/' "$SCRIPT_CONF"
	
	Print_Output true "Scheduled update created for VPN client $VPN_NO" "$PASS"
}

CancelScheduleVPN(){
	VPN_NO="$1"
	
	Print_Output true "Removing scheduled update for VPN client $VPN_NO"
		
	if cru l | grep -q "${SCRIPT_NAME}_VPN${VPN_NO}"; then
		cru d "${SCRIPT_NAME}_VPN${VPN_NO}"
	fi
	
	sed -i 's/^vpn'"$VPN_NO"'_schenabled.*$/vpn'"$VPN_NO"'_schenabled=false/' "$SCRIPT_CONF"
	
	if grep -q "${SCRIPT_NAME}_VPN${VPN_NO}" /jffs/scripts/services-start; then
		sed -i "/${SCRIPT_NAME}_VPN${VPN_NO}/d" /jffs/scripts/services-start
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
	ScriptHeader
	ListVPNClients false "$1"
	printf "Choose options as follows:\\n"
	printf "    - VPN client (pick from list)\\n"
	printf "\\n"
	printf "${BOLD}#########################################################${CLEARFORMAT}\\n"
	
	exitmenu=""
	vpnnum=""
	
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
		GLOBAL_VPN_NO="$vpnnum"
		return 0
	else
		printf "\\n"
		return 1
	fi
}

SetVPNParameters(){
	exitmenu=""
	vpnnum=""
	vpnprovider=""
	vpnprot=""
	vpntype=""
	choosecountry=""
	choosecity=""
	countryname=""
	countryid=0
	cityname=""
	cityid=0
	
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
		LISTCOUNTRIES="$("provider_${vpnprovider_lc}_get_country_names")"
		[ -z "$LISTCOUNTRIES" ] && Print_Output true "Error, country data for $vpnprovider is missing" "$ERR" && return 1
		COUNTCOUNTRIES="$(printf '%s\n' "$LISTCOUNTRIES" | wc -l)"
		while true; do
			printf "\\n${BOLD}Please select a country:${CLEARFORMAT}\\n"
			printf '%s\n' "$LISTCOUNTRIES" | awk -v total="$COUNTCOUNTRIES" '
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

			printf "\\nChoose an option:  "
			read -r country_choice

			if [ "$country_choice" = "e" ]; then
				exitmenu="exit"
				break
			elif ! Validate_Number "$country_choice"; then
				printf "\\n\\e[31mPlease enter a valid number (1-%s)${CLEARFORMAT}\\n" "$COUNTCOUNTRIES"
			else
				if [ "$country_choice" -lt 1 ] || [ "$country_choice" -gt "$COUNTCOUNTRIES" ]; then
					printf "\\n\\e[31mPlease enter a number between 1 and %s${CLEARFORMAT}\\n" "$COUNTCOUNTRIES"
				else
					countryname="$(printf '%s\n' "$LISTCOUNTRIES" | sed -n "${country_choice}p")"
					countryid="$("provider_${vpnprovider_lc}_get_country_id" "$countryname")"
					printf "\\n"
					break
				fi
			fi
		done

		if [ "$exitmenu" != "exit" ]; then
			citycount="$("provider_${vpnprovider_lc}_get_city_count" "$countryname")"

			if [ "$citycount" -eq 1 ]; then
				cityname="$("provider_${vpnprovider_lc}_get_city_names" "$countryname")"
				cityid="$("provider_${vpnprovider_lc}_get_city_id" "$countryname" "$cityname")"
			elif [ "$citycount" -gt 1 ]; then
				if "provider_${vpnprovider_lc}_city_required"; then
					choosecity="true"
				else
					while true; do
						printf "\\n${BOLD}Would you like to select a city (y/n)?${CLEARFORMAT}  "
						read -r city_select

						if [ "$city_select" = "e" ]; then
							exitmenu="exit"
							break
						elif [ "$city_select" = "n" ] || [ "$city_select" = "N" ]; then
							choosecity="false"
							printf "\\n"
							break
						elif [ "$city_select" = "y" ] || [ "$city_select" = "Y" ]; then
							choosecity="true"
							break
						else
							printf "\\n\\e[31mPlease enter y or n${CLEARFORMAT}\\n"
						fi
					done
				fi
			fi
		fi

		if [ "$choosecity" = "true" ]; then
			LISTCITIES="$("provider_${vpnprovider_lc}_get_city_names" "$countryname")"
			COUNTCITIES="$(printf '%s\n' "$LISTCITIES" | wc -l)"
			while true; do
				printf "\\n${BOLD}Please select a city:${CLEARFORMAT}\\n"
				printf '%s\n' "$LISTCITIES" | awk '{ printf "  %3d. %s\n", NR, $0 }'

				printf "\\nChoose an option:  "
				read -r city_choice

				if [ "$city_choice" = "e" ]; then
					exitmenu="exit"
					break
				elif ! Validate_Number "$city_choice"; then
					printf "\\n\\e[31mPlease enter a valid number (1-%s)${CLEARFORMAT}\\n" "$COUNTCITIES"
				else
					if [ "$city_choice" -lt 1 ] || [ "$city_choice" -gt "$COUNTCITIES" ]; then
						printf "\\n\\e[31mPlease enter a number between 1 and %s${CLEARFORMAT}\\n" "$COUNTCITIES"
					else
						cityname="$(printf '%s\n' "$LISTCITIES" | sed -n "${city_choice}p")"
						cityid="$("provider_${vpnprovider_lc}_get_city_id" "$countryname" "$cityname")"
						printf "\\n"
						break
					fi
				fi
			done
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
	vpncustomoptions='remote-random
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

	# persist-key and fast-io are ignored no-ops from OpenVPN 2.6 onwards (key
	# persistence is automatic, fast-io was removed). Only add them for older clients.
	VPN_OVPNVER="$(OpenVPN_Version_Number)"
	if [ -z "$VPN_OVPNVER" ] || [ "$VPN_OVPNVER" -lt 2006000 ]; then
		vpncustomoptions="$vpncustomoptions
persist-key
fast-io"
	fi

	VPN_MUTE="$(grep "vpn${VPN_NO}_mute" "$SCRIPT_CONF" | cut -f2 -d"=")"
	[ -z "$VPN_MUTE" ] && VPN_MUTE="20"
	if Validate_Number "$VPN_MUTE" && [ "$VPN_MUTE" -gt 0 ]; then
		vpncustomoptions="$vpncustomoptions
mute $VPN_MUTE"
	fi

	VPN_DEBUGVERB="$(grep "vpn${VPN_NO}_debugverb" "$SCRIPT_CONF" | cut -f2 -d"=")"
	if [ "$VPN_DEBUGVERB" = "true" ]; then
		vpncustomoptions="$vpncustomoptions
verb 4"
	fi

	if [ "$VPN_PROT_SHORT" = "UDP" ]; then
		vpncustomoptions="$vpncustomoptions
explicit-exit-notify 3"
	fi
	
	if [ "$VPN_PROVIDER" = "NordVPN" ]; then
		vpncustomoptions="$vpncustomoptions
tun-mtu 1500
tun-mtu-extra 32
mssfix 1450"
	fi
	
	if [ "$(Firmware_Number_Check "$(nvram get buildno)")" -lt "$(Firmware_Number_Check 386.3)" ]; then
		vpncustomoptionsbase64="$(echo "$vpncustomoptions" | head -c -1 | openssl base64 -A)"
		
		if [ "$(/bin/uname -m)" = "aarch64" ]; then
			nvram set vpn_client"$VPN_NO"_cust2="$(echo "$vpncustomoptionsbase64" | cut -c0-255)"
			nvram set vpn_client"$VPN_NO"_cust21="$(echo "$vpncustomoptionsbase64" | cut -c256-510)"
			nvram set vpn_client"$VPN_NO"_cust22="$(echo "$vpncustomoptionsbase64" | cut -c511-765)"
		elif [ "$(uname -o)" = "ASUSWRT-Merlin" ]; then
			nvram set vpn_client"$VPN_NO"_cust2="$vpncustomoptionsbase64"
		else
			nvram set vpn_client"$VPN_NO"_custom="$vpncustomoptions"
		fi
		nvram commit
	else
		printf "%s" "$vpncustomoptions" > /jffs/openvpn/vpn_client"$VPN_NO"_custom3
	fi
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
					if SetVPNClient hide; then
						if [ "$(grep "vpn${GLOBAL_VPN_NO}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
							Print_Output false "VPN client $GLOBAL_VPN_NO is not managed, cannot search for new server" "$ERR"
							break
						fi
						UpdateVPNConfig unattended "$GLOBAL_VPN_NO"
					fi
					Clear_Lock
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
				if SetVPNClient hide; then
					if [ "$(grep "vpn${GLOBAL_VPN_NO}_managed" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
						Print_Output false "VPN client $GLOBAL_VPN_NO is not managed, cannot apply custom settings" "$ERR"
						break
					fi
					if [ "$(grep "vpn${GLOBAL_VPN_NO}_customsettings" "$SCRIPT_CONF" | cut -f2 -d"=")" = "false" ]; then
						sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_customsettings.*$/vpn'"$GLOBAL_VPN_NO"'_customsettings=true/' "$SCRIPT_CONF"
						SetVPNCustomSettings "$GLOBAL_VPN_NO"
					else
						sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_customsettings.*$/vpn'"$GLOBAL_VPN_NO"'_customsettings=false/' "$SCRIPT_CONF"
					fi
				fi
				PressEnter
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
					sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_mute.*$/vpn'"$GLOBAL_VPN_NO"'_mute='"$mute_choice"'/' "$SCRIPT_CONF"
					sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_debugverb.*$/vpn'"$GLOBAL_VPN_NO"'_debugverb='"$debugverb_choice"'/' "$SCRIPT_CONF"
					if [ "$(grep "vpn${GLOBAL_VPN_NO}_customsettings" "$SCRIPT_CONF" | cut -f2 -d"=")" = "true" ]; then
						SetVPNCustomSettings "$GLOBAL_VPN_NO"
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
	printf "    - country/city of VPN Server (pick from list)\\n"
	printf "\\n"
	printf "${BOLD}#########################################################${CLEARFORMAT}\\n"
	
	if SetVPNParameters; then
		sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_provider.*$/vpn'"$GLOBAL_VPN_NO"'_provider='"$GLOBAL_VPN_PROVIDER"'/' "$SCRIPT_CONF"
		sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_type.*$/vpn'"$GLOBAL_VPN_NO"'_type='"$GLOBAL_VPN_TYPE"'/' "$SCRIPT_CONF"
		sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_protocol.*$/vpn'"$GLOBAL_VPN_NO"'_protocol='"$GLOBAL_VPN_PROT"'/' "$SCRIPT_CONF"
		sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_countryname.*$/vpn'"$GLOBAL_VPN_NO"'_countryname='"$GLOBAL_COUNTRY_NAME"'/' "$SCRIPT_CONF"
		sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_countryid.*$/vpn'"$GLOBAL_VPN_NO"'_countryid='"$GLOBAL_COUNTRY_ID"'/' "$SCRIPT_CONF"
		sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_cityname.*$/vpn'"$GLOBAL_VPN_NO"'_cityname='"$GLOBAL_CITY_NAME"'/' "$SCRIPT_CONF"
		sed -i 's/^vpn'"$GLOBAL_VPN_NO"'_cityid.*$/vpn'"$GLOBAL_VPN_NO"'_cityid='"$GLOBAL_CTIY_ID"'/' "$SCRIPT_CONF"
		UpdateVPNConfig "$GLOBAL_VPN_NO"
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
	
	Create_Dirs
	Conf_Exists
	Create_Symlinks
	Auto_Cron create 2>/dev/null
	Auto_Startup create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	
	Update_File vpnmgr_www.asp
	Update_File vpnmgr_www.js
	Update_File web-assets

	Install_Providers
	Refresh_Provider_Cache

	Set_Version_Custom_Settings local "$SCRIPT_VERSION"
	Set_Version_Custom_Settings server "$SCRIPT_VERSION"
	Shortcut_Script create
	Clear_Lock

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
	Refresh_Provider_Cache

	Create_Symlinks
	ScriptHeader
	MainMenu
	exit 0
fi

case "$1" in
	install)
		Check_Lock
		Menu_Install
		exit 0
	;;
	updatevpn)
		NTP_Ready
		Entware_Ready
		UpdateVPNConfig unattended "$2"
		exit 0
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
			exit 0
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME}doupdate" ]; then
			Update_Version force
			exit 0
		fi
		exit 0
	;;
	update)
		Update_Version
		exit 0
	;;
	forceupdate)
		Update_Version force
		exit 0
	;;
	setversion)
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
		Install_Providers
		Refresh_Provider_Cache
		Create_Symlinks
		exit 0
	;;
	postupdate)
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
		Install_Providers
		Refresh_Provider_Cache
		Create_Symlinks
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
		SCRIPT_REPO="https://raw.githubusercontent.com/h0me5k1n/$SCRIPT_NAME/$SCRIPT_BRANCH"
		Update_Version force
		exit 0
	;;
	stable)
		SCRIPT_BRANCH="main"
		SCRIPT_REPO="https://raw.githubusercontent.com/h0me5k1n/$SCRIPT_NAME/$SCRIPT_BRANCH"
		Update_Version force
		exit 0
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
