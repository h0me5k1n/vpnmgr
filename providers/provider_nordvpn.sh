#!/bin/sh
# NordVPN provider module for vpnmgr
# Status: UNTESTED
# Display: NordVPN
# Config: NordVPN
#
# Depends on: jq, curl
# Cache file: $SCRIPT_DIR/nordvpn_countrydata  (JSON array from NordVPN API)

##########         Shellcheck directives     ##########
# shellcheck disable=SC2039
# shellcheck disable=SC3043
#######################################################

provider_nordvpn_version(){
	printf "v1.0.0\n"
}

# Map human-readable type names to NordVPN API group identifiers
_nordvpn_type_to_api(){
	case "$1" in
		Standard)   printf "legacy_standard" ;;
		Double)     printf "legacy_double_vpn" ;;
		P2P)        printf "legacy_p2p" ;;
		Obfuscated) printf "legacy_obfuscated" ;;
		*)          printf "legacy_standard" ;;
	esac
}

# Map protocol SHORT (UDP/TCP) to NordVPN technology identifier
_nordvpn_prot_to_api(){
	case "$1" in
		UDP) printf "openvpn_udp" ;;
		TCP) printf "openvpn_tcp" ;;
		*)   printf "openvpn_udp" ;;
	esac
}

# provider_nordvpn_get_server country_id country_name city_id city_name protocol vpn_type
# Prints the server hostname on stdout.
provider_nordvpn_get_server(){
	_nord_countryid="$1"
	_nord_cityid="$3"
	_nord_prot="$5"
	_nord_type="$6"

	_nord_api_type="$(_nordvpn_type_to_api "$_nord_type")"
	_nord_api_prot="$(_nordvpn_prot_to_api "$_nord_prot")"

	_nord_vjson=""

	if [ "$_nord_countryid" -eq 0 ] 2>/dev/null || [ -z "$_nord_countryid" ]; then
		# No country filter — worldwide
		_nord_vjson="$(_nordvpn_get_recommended "$_nord_api_type" "$_nord_api_prot" 0)"
	elif [ "$_nord_cityid" -eq 0 ] 2>/dev/null || [ -z "$_nord_cityid" ]; then
		# Country only
		_nord_vjson="$(_nordvpn_get_recommended "$_nord_api_type" "$_nord_api_prot" "$_nord_countryid")"
	else
		# City + country
		_nord_vjson="$(_nordvpn_get_city "$_nord_api_type" "$_nord_api_prot" "$_nord_countryid" "$_nord_cityid")"
		if [ -z "$_nord_vjson" ]; then
			Print_Output true "NordVPN: No server found for city, falling back to country" "$WARN"
			_nord_vjson="$(_nordvpn_get_recommended "$_nord_api_type" "$_nord_api_prot" "$_nord_countryid")"
		fi
		if [ -z "$_nord_vjson" ]; then
			Print_Output true "NordVPN: No server found for country, falling back to worldwide" "$WARN"
			_nord_vjson="$(_nordvpn_get_recommended "$_nord_api_type" "$_nord_api_prot" 0)"
		fi
	fi

	[ -z "$_nord_vjson" ] && Print_Output true "NordVPN: API returned no servers" "$ERR" && return 1

	_nord_hostname="$(printf '%s' "$_nord_vjson" | jq -r -e '.hostname // empty')"
	[ -z "$_nord_hostname" ] && Print_Output true "NordVPN: Could not determine hostname" "$ERR" && return 1

	_nord_load="$(printf '%s' "$_nord_vjson" | jq -r '.load // empty')"
	if [ -n "$_nord_load" ]; then
		printf '%s' "$_nord_load" > "$SCRIPT_DIR/nordvpn_load_${_nord_hostname%%.*}"
	fi

	_nord_country_name="$(printf '%s' "$_nord_vjson" | jq -r '.locations[0].country.name // empty')"
	_nord_country_code="$(printf '%s' "$_nord_vjson" | jq -r '.locations[0].country.code // empty')"
	_nord_city_name="$(printf '%s' "$_nord_vjson" | jq -r '.locations[0].country.city.name // empty')"
	printf '%s|%s|%s\n' "$_nord_country_name" "$_nord_country_code" "$_nord_city_name" \
		> "$SCRIPT_DIR/nordvpn_meta_${_nord_hostname%%.*}"

	printf '%s' "$_nord_hostname"
}

_nordvpn_get_recommended(){
	_nr_type="$1"
	_nr_prot="$2"
	_nr_cid="$3"
	_nr_url="https://api.nordvpn.com/v1/servers/recommendations?filters[servers_groups][identifier]=${_nr_type}&filters[servers_technologies][identifier]=${_nr_prot}"
	if [ "$_nr_cid" -ne 0 ] 2>/dev/null; then
		_nr_url="${_nr_url}&filters[country_id]=${_nr_cid}"
	fi
	_nr_url="${_nr_url}&limit=1"
	/usr/sbin/curl --globoff -fsL --retry 3 "$_nr_url" | jq -r -e '.[] // empty'
}

_nordvpn_get_city(){
	_nc_type="$1"
	_nc_prot="$2"
	_nc_cid="$3"
	_nc_cityid="$4"
	/usr/sbin/curl --globoff -fsL --retry 3 \
		"https://api.nordvpn.com/v1/servers/recommendations?filters[servers_groups][identifier]=${_nc_type}&filters[servers_technologies][identifier]=${_nc_prot}&filters[country_id]=${_nc_cid}&limit=2500" \
		| jq -r -e "[ .[] | select(.locations[].country.city.id==${_nc_cityid})][0] // empty"
}

# provider_nordvpn_get_ovpn hostname protocol vpn_type [legacy|modern]
# Downloads OVPN file from NordVPN CDN and prints contents to stdout.
# The core passes its detected family explicitly. Independent consumers keep
# the historical legacy route unless they explicitly request modern profiles.
provider_nordvpn_get_ovpn(){
	_gov_hostname="$1"
	_gov_prot="$2"
	_gov_prot_lc="$(printf '%s' "$_gov_prot" | tr 'A-Z' 'a-z')"
	case "${4:-legacy}" in
		legacy) _gov_suffix="" ;;
		modern) _gov_suffix="_2.6" ;;
		*) return 1 ;;
	esac
	/usr/sbin/curl -fsL --retry 3 \
		"https://downloads.nordcdn.com/configs/files/ovpn_${_gov_prot_lc}/servers/${_gov_hostname}.${_gov_prot_lc}${_gov_suffix}.ovpn"
}

# provider_nordvpn_get_comp
provider_nordvpn_get_comp(){
	printf -- "-1"
}

# provider_nordvpn_get_hmac
provider_nordvpn_get_hmac(){
	# The no-argument form is retained for standalone legacy API consumers.
	[ "$#" -eq 0 ] && { printf '1'; return 0; }
	case "$1" in
		*'<tls-crypt>'*) printf '3' ;;
		*'<tls-auth>'*)
			_nh_direction="$(printf '%s\n' "$1" | awk '$1 == "key-direction" { sub(/\r$/, "", $2); print $2; exit }')"
			case "$_nh_direction" in
				0|1) printf '%s' "$_nh_direction" ;;
				'') printf '2' ;;
				*) return 1 ;;
			esac ;;
		*) return 1 ;;
	esac
}

# Parse exactly one complete inline block; never return partial key material.
_nordvpn_profile_block(){
	printf '%s\n' "$1" | awk -v tag="$2" '
		{ sub(/\r$/, "") }
		$0 == "<" tag ">" { if (open || seen) bad=1; open=1; seen++ ; next }
		$0 == "</" tag ">" { if (!open) bad=1; open=0; closed++; next }
		open { if ($0 !~ /^#/) { body=body $0 "\n"; if ($0 !~ /^[[:space:]]*$/) nonempty=1 } }
		END { if (!bad && seen==1 && closed==1 && !open && nonempty) printf "%s", body; else exit 1 }
	'
}

provider_nordvpn_preflight(){
	_np_profile="$(printf '%s\n' "$1" | tr -d '\r')"
	_np_ca="$(_nordvpn_profile_block "$_np_profile" ca)" || return 1
	case "$_np_ca" in *'BEGIN CERTIFICATE'*'END CERTIFICATE'*) ;; *) return 1 ;; esac
	printf '%s\n' "$_np_ca" | openssl x509 -noout >/dev/null 2>&1 || return 1
	case "$_np_profile" in
		*'<tls-auth>'*'<tls-crypt>'*|*'<tls-crypt>'*'<tls-auth>'*) return 1 ;;
		*'<tls-crypt>'*) _np_tag=tls-crypt ;;
		*'<tls-auth>'*) _np_tag=tls-auth ;;
		*) return 1 ;;
	esac
	_np_static="$(_nordvpn_profile_block "$_np_profile" "$_np_tag")" || return 1
	printf '%s\n' "$_np_static" | awk '
		NR==1 { if ($0 != "-----BEGIN OpenVPN Static key V1-----") exit 1; next }
		/^-----END OpenVPN Static key V1-----$/ { if (NR != 18) exit 1; ended=1; next }
		{ if (ended || length($0) != 32 || $0 !~ /^[[:xdigit:]]+$/) exit 1 }
		END { if (!ended || NR != 18) exit 1 }
	' || return 1
	_np_mode="$(provider_nordvpn_get_hmac "$_np_profile")" || return 1
	_np_direction_count="$(printf '%s\n' "$_np_profile" | awk '$1 == "key-direction" { n++ } END { print n+0 }')"
	[ "$_np_direction_count" -le 1 ] || return 1
	if [ "$_np_tag" = tls-crypt ] && printf '%s\n' "$_np_profile" | grep -Eq '^[[:space:]]*key-direction[[:space:]]'; then
		return 1
	fi
	return 0
}

# provider_nordvpn_get_short_name hostname addr
provider_nordvpn_get_short_name(){
	printf '%s' "$1" | cut -f1 -d'.' | tr 'a-z' 'A-Z'
}

# provider_nordvpn_get_desc hostname short_name protocol vpn_type
# Prints the nvram vpn_clientX_desc value using the actual selected
# server's location, cached by get_server() at selection time:
#   Country Name (CC) - City Name [PROTOCOL] [VPN Type] - server-id
# Falls back to a compact form under Merlin's 25-char Description limit:
#   CC CityAbbrev PROTO TypeAbbr server-id
provider_nordvpn_get_desc(){
	_gd_hostname="$1"; _gd_short="$2"; _gd_prot="$3"; _gd_type="$4"
	_gd_meta="$SCRIPT_DIR/nordvpn_meta_${_gd_hostname%%.*}"
	_gd_country=""; _gd_cc=""; _gd_city=""
	[ -f "$_gd_meta" ] && IFS='|' read -r _gd_country _gd_cc _gd_city < "$_gd_meta"
	[ -z "$_gd_country" ] && _gd_country="Unknown"
	_gd_serverid="$(printf '%s' "$_gd_short" | tr 'A-Z' 'a-z')"
	_gd_city_full="$_gd_city"; [ -z "$_gd_city_full" ] && _gd_city_full="Country Wide"

	if [ -n "$_gd_cc" ]; then
		_gd_full="${_gd_country} (${_gd_cc}) - ${_gd_city_full} [${_gd_prot}] [${_gd_type}] - ${_gd_serverid}"
	else
		_gd_full="${_gd_country} - ${_gd_city_full} [${_gd_prot}] [${_gd_type}] - ${_gd_serverid}"
	fi

	if [ "${#_gd_full}" -le 25 ]; then
		printf '%s' "$_gd_full"
		return 0
	fi

	# Compact fallback — reserve space for the fixed parts (CC, protocol,
	# type abbreviation, server id) before truncating the city name.
	_gd_type_abbr="Std"
	case "$_gd_type" in
		Double) _gd_type_abbr="Dbl" ;;
		P2P)    _gd_type_abbr="P2P" ;;
	esac
	_gd_city_out="$_gd_city"; [ -z "$_gd_city_out" ] && _gd_city_out="Wide"
	_gd_fixed=" ${_gd_prot} ${_gd_type_abbr} ${_gd_serverid}"
	if [ -n "$_gd_cc" ]; then
		_gd_fixed="${_gd_cc}${_gd_fixed}"
	fi
	_gd_budget=$((25 - ${#_gd_fixed} - 1))
	[ "$_gd_budget" -lt 1 ] && _gd_budget=1
	_gd_city_out="$(printf '%s' "$_gd_city_out" | cut -c"1-${_gd_budget}" | sed 's/ *$//')"
	if [ -n "$_gd_cc" ]; then
		printf '%s %s %s %s %s' "$_gd_cc" "$_gd_city_out" "$_gd_prot" "$_gd_type_abbr" "$_gd_serverid"
	else
		printf '%s %s %s %s' "$_gd_city_out" "$_gd_prot" "$_gd_type_abbr" "$_gd_serverid"
	fi
}

# provider_nordvpn_write_certs vpn_no ovpn_detail
# Writes the validated inline CA and tls-auth/tls-crypt static key.
provider_nordvpn_write_certs(){
	_wc_no="$1"
	_wc_ovpn="$2"

	provider_nordvpn_preflight "$_wc_ovpn" || { Print_Output true "NordVPN: Invalid CA or TLS key material" "$ERR"; return 1; }
	_wc_ca="$(_nordvpn_profile_block "$_wc_ovpn" ca)"
	[ -z "$_wc_ca" ] && Print_Output true "NordVPN: Error determining CA certificate" "$ERR" && return 1

	_wc_tag=tls-auth
	case "$_wc_ovpn" in *'<tls-crypt>'*) _wc_tag=tls-crypt ;; esac
	_wc_static="$(_nordvpn_profile_block "$_wc_ovpn" "$_wc_tag")"

	printf '%s\n' "$_wc_ca"     > /jffs/openvpn/vpn_crt_client"${_wc_no}"_ca || return 1
	printf '%s\n' "$_wc_static" > /jffs/openvpn/vpn_crt_client"${_wc_no}"_static || return 1
	rm -f /jffs/openvpn/vpn_crt_client"${_wc_no}"_crl || return 1
	rm -f /jffs/openvpn/vpn_crt_client"${_wc_no}"_key || return 1
	rm -f /jffs/openvpn/vpn_crt_client"${_wc_no}"_crt || return 1
}

# provider_nordvpn_get_country_names
# Reads cached country data JSON and prints country names, one per line.
provider_nordvpn_get_country_names(){
	_cdata="$SCRIPT_DIR/nordvpn_countrydata"
	if [ ! -f "$_cdata" ]; then
		Print_Output true "NordVPN: Country data cache missing — run refreshcacheddata" "$ERR"
		return 1
	fi
	jq -r -e '.[] | .name // empty' "$_cdata"
}

# provider_nordvpn_get_country_id country_name
provider_nordvpn_get_country_id(){
	_cdata="$SCRIPT_DIR/nordvpn_countrydata"
	jq -r -e ".[] | select(.name==\"$1\") | .id // empty" "$_cdata"
}

# provider_nordvpn_get_city_count country_name
provider_nordvpn_get_city_count(){
	_cdata="$SCRIPT_DIR/nordvpn_countrydata"
	jq -r -e ".[] | select(.name==\"$1\") | .cities | length // empty" "$_cdata"
}

# provider_nordvpn_get_city_names country_name
provider_nordvpn_get_city_names(){
	_cdata="$SCRIPT_DIR/nordvpn_countrydata"
	jq -r -e ".[] | select(.name==\"$1\") | .cities[] | .name // empty" "$_cdata"
}

# provider_nordvpn_get_city_id country_name city_name
provider_nordvpn_get_city_id(){
	_cdata="$SCRIPT_DIR/nordvpn_countrydata"
	jq -r -e ".[] | select(.name==\"$1\") | .cities[] | select(.name==\"$2\") | .id // empty" "$_cdata"
}

# provider_nordvpn_country_required
# Returns 1 — country selection is optional for NordVPN.
provider_nordvpn_country_required(){
	return 1
}

# provider_nordvpn_city_required
# Returns 1 — city selection is optional for NordVPN.
provider_nordvpn_city_required(){
	return 1
}

# provider_nordvpn_get_types
# Prints available VPN types, one per line.
provider_nordvpn_get_types(){
	printf "Standard\nDouble\nP2P\n"
}

# provider_nordvpn_get_server_load desc
# desc: nvram vpn_clientX_desc value. Handles the legacy format
# ("NordVPN <hostname_short> <type> <proto>", server id is the 2nd
# token) and the full/compact formats from get_desc() (server id is
# always the last whitespace-separated token in both).
# Reads load written by get_server at selection time.
# NordVPN /server/stats/ API was deprecated; load is cached from recommendations response.
provider_nordvpn_get_server_load(){
	_sl_desc="$1"
	case "$_sl_desc" in
		"NordVPN "*) _sl_id="$(printf '%s' "$_sl_desc" | cut -f2 -d ' ')" ;;
		*)           _sl_id="${_sl_desc##* }" ;;
	esac
	_sl_short="$(printf '%s' "$_sl_id" | tr 'A-Z' 'a-z')"
	_sl_cache="$SCRIPT_DIR/nordvpn_load_${_sl_short}"
	if [ -f "$_sl_cache" ]; then
		cat "$_sl_cache"
	else
		printf 'Unknown\n'
	fi
}

# provider_nordvpn_refresh_cache
# Downloads NordVPN country data, compares with cached copy, updates if changed.
provider_nordvpn_refresh_cache(){
	Print_Output true "NordVPN: Refreshing country data..."
	/usr/sbin/curl -fsL --retry 3 "https://api.nordvpn.com/v1/servers/countries" \
		| jq -r > /tmp/nordvpn_countrydata
	_rc_data="$(cat /tmp/nordvpn_countrydata)"
	if [ -z "$_rc_data" ]; then
		Print_Output true "NordVPN: Country data failed to download" "$ERR"
		rm -f /tmp/nordvpn_countrydata
		return 1
	fi
	if [ -f "$SCRIPT_DIR/nordvpn_countrydata" ]; then
		if ! diff -q /tmp/nordvpn_countrydata "$SCRIPT_DIR/nordvpn_countrydata" >/dev/null 2>&1; then
			mv /tmp/nordvpn_countrydata "$SCRIPT_DIR/nordvpn_countrydata"
			Print_Output true "NordVPN: Country data updated" "$PASS"
			Create_Symlinks
		else
			rm -f /tmp/nordvpn_countrydata
			Print_Output true "NordVPN: Country data unchanged" "$WARN"
		fi
	else
		mv /tmp/nordvpn_countrydata "$SCRIPT_DIR/nordvpn_countrydata"
		Create_Symlinks
		Print_Output true "NordVPN: Country data downloaded (first run)" "$PASS"
	fi
}

# provider_nordvpn_needs_cache
# Returns 0 (needs refresh) if cache file is missing, 1 if present.
provider_nordvpn_needs_cache(){
	if [ ! -f "$SCRIPT_DIR/nordvpn_countrydata" ]; then
		return 0
	fi
	return 1
}
