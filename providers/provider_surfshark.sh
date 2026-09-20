#!/bin/sh
# Provider: Surfshark
# Status: UNTESTED
# Display: Surfshark
# Config: Surfshark
# Description: Surfshark VPN — 100 countries, 142 server locations.
# API: https://api.surfshark.com/v4/server/clusters
# Depends on: jq, curl
# Cache file: $SCRIPT_DIR/surfshark_serverdata  (JSON array from Surfshark API)

##########         Shellcheck directives     ##########
# shellcheck disable=SC2039
# shellcheck disable=SC3043
#######################################################

_SURFSHARK_API="https://api.surfshark.com/v4/server/clusters"

provider_surfshark_version(){
	printf "v1.0.0\n"
}

# provider_surfshark_refresh_cache
# Downloads server list and caches to $SCRIPT_DIR/surfshark_serverdata.
provider_surfshark_refresh_cache(){
	Print_Output true "Surfshark: Refreshing server data..."
	/usr/sbin/curl -fsL --retry 3 "$_SURFSHARK_API" > /tmp/surfshark_serverdata
	_ss_rc_data="$(cat /tmp/surfshark_serverdata)"
	if [ -z "$_ss_rc_data" ] || ! printf '%s' "$_ss_rc_data" | jq -e '.[0].connectionName' >/dev/null 2>&1; then
		Print_Output true "Surfshark: Server data failed to download" "$ERR"
		rm -f /tmp/surfshark_serverdata
		return 1
	fi
	if [ -f "$SCRIPT_DIR/surfshark_serverdata" ]; then
		if ! diff -q /tmp/surfshark_serverdata "$SCRIPT_DIR/surfshark_serverdata" >/dev/null 2>&1; then
			mv /tmp/surfshark_serverdata "$SCRIPT_DIR/surfshark_serverdata"
			Print_Output true "Surfshark: Server data updated" "$PASS"
			Create_Symlinks
		else
			rm -f /tmp/surfshark_serverdata
			Print_Output true "Surfshark: Server data unchanged" "$WARN"
		fi
	else
		mv /tmp/surfshark_serverdata "$SCRIPT_DIR/surfshark_serverdata"
		Create_Symlinks
		Print_Output true "Surfshark: Server data downloaded (first run)" "$PASS"
	fi
}

# provider_surfshark_get_server country_id country_name city_id city_name protocol vpn_type
# country_id: ISO country code (e.g. "GB")
# city_id: city name / location (e.g. "London") — same as city_name; "0" or "" means any city
# Returns the server hostname with lowest load matching the criteria.
provider_surfshark_get_server(){
	_ss_gs_cc="$1"
	_ss_gs_cityid="$3"
	_ss_gs_data="$SCRIPT_DIR/surfshark_serverdata"
	_ss_gs_hostname=""

	[ ! -f "$_ss_gs_data" ] && Print_Output true "Surfshark: Cache missing — run refreshcacheddata" "$ERR" && return 1

	if [ -n "$_ss_gs_cityid" ] && [ "$_ss_gs_cityid" != "0" ]; then
		_ss_gs_hostname="$(jq -r --arg cc "$_ss_gs_cc" --arg city "$_ss_gs_cityid" \
			'[.[] | select(.countryCode==$cc and .location==$city)] | sort_by(.load) | .[0].connectionName // empty' \
			"$_ss_gs_data")"
		if [ -z "$_ss_gs_hostname" ]; then
			Print_Output true "Surfshark: No server for city, falling back to country" "$WARN"
		fi
	fi

	if [ -z "$_ss_gs_hostname" ] && [ -n "$_ss_gs_cc" ] && [ "$_ss_gs_cc" != "0" ]; then
		_ss_gs_hostname="$(jq -r --arg cc "$_ss_gs_cc" \
			'[.[] | select(.countryCode==$cc)] | sort_by(.load) | .[0].connectionName // empty' \
			"$_ss_gs_data")"
		if [ -z "$_ss_gs_hostname" ]; then
			Print_Output true "Surfshark: No server for country, falling back to worldwide" "$WARN"
		fi
	fi

	if [ -z "$_ss_gs_hostname" ]; then
		_ss_gs_hostname="$(jq -r '[.[] ] | sort_by(.load) | .[0].connectionName // empty' "$_ss_gs_data")"
	fi

	[ -z "$_ss_gs_hostname" ] && Print_Output true "Surfshark: API returned no servers" "$ERR" && return 1

	_ss_gs_load="$(jq -r --arg h "$_ss_gs_hostname" \
		'.[] | select(.connectionName==$h) | .load // empty' "$_ss_gs_data")"
	[ -n "$_ss_gs_load" ] && printf '%s' "$_ss_gs_load" > "$SCRIPT_DIR/surfshark_load_${_ss_gs_hostname%%.*}"

	printf '%s' "$_ss_gs_hostname"
}

# provider_surfshark_get_ovpn hostname protocol vpn_type
# Builds and prints the OVPN config. CA cert and TLS-auth key are embedded.
provider_surfshark_get_ovpn(){
	_ss_gov_hostname="$1"
	_ss_gov_prot="$2"
	_ss_gov_prot_lc="$(printf '%s' "$_ss_gov_prot" | tr 'A-Z' 'a-z')"

	case "$_ss_gov_prot_lc" in
		udp) _ss_gov_port="1194" ;;
		tcp) _ss_gov_port="1443" ;;
		*)   _ss_gov_prot_lc="udp"; _ss_gov_port="1194" ;;
	esac

	cat <<EOF
client
dev tun
proto ${_ss_gov_prot_lc}
remote ${_ss_gov_hostname} ${_ss_gov_port}
remote-random
nobind
tun-mtu 1500
mssfix 1450
ping 15
ping-restart 0
reneg-sec 0

remote-cert-tls server

auth-user-pass

verb 3
cipher AES-256-CBC

auth SHA512

<ca>
-----BEGIN CERTIFICATE-----
MIIFTTCCAzWgAwIBAgIJAMs9S3fqwv+mMA0GCSqGSIb3DQEBCwUAMD0xCzAJBgNV
BAYTAlZHMRIwEAYDVQQKDAlTdXJmc2hhcmsxGjAYBgNVBAMMEVN1cmZzaGFyayBS
b290IENBMB4XDTE4MDMxNDA4NTkyM1oXDTI4MDMxMTA4NTkyM1owPTELMAkGA1UE
BhMCVkcxEjAQBgNVBAoMCVN1cmZzaGFyazEaMBgGA1UEAwwRU3VyZnNoYXJrIFJv
b3QgQ0EwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDEGMNj0aisM63o
SkmVJyZPaYX7aPsZtzsxo6m6p5Wta3MGASoryRsBuRaH6VVa0fwbI1nw5ubyxkua
Na4v3zHVwuSq6F1p8S811+1YP1av+jqDcMyojH0ujZSHIcb/i5LtaHNXBQ3qN48C
c7sqBnTIIFpmb5HthQ/4pW+a82b1guM5dZHsh7q+LKQDIGmvtMtO1+NEnmj81BAp
FayiaD1ggvwDI4x7o/Y3ksfWSCHnqXGyqzSFLh8QuQrTmWUm84YHGFxoI1/8AKdI
yVoB6BjcaMKtKs/pbctk6vkzmYf0XmGovDKPQF6MwUekchLjB5gSBNnptSQ9kNgn
TLqi0OpSwI6ixX52Ksva6UM8P01ZIhWZ6ua/T/tArgODy5JZMW+pQ1A6L0b7egIe
ghpwKnPRG+5CzgO0J5UE6gv000mqbmC3CbiS8xi2xuNgruAyY2hUOoV9/BuBev8t
tE5ZCsJH3YlG6NtbZ9hPc61GiBSx8NJnX5QHyCnfic/X87eST/amZsZCAOJ5v4EP
SaKrItt+HrEFWZQIq4fJmHJNNbYvWzCE08AL+5/6Z+lxb/Bm3dapx2zdit3x2e+m
iGHekuiE8lQWD0rXD4+T+nDRi3X+kyt8Ex/8qRiUfrisrSHFzVMRungIMGdO9O/z
CINFrb7wahm4PqU2f12Z9TRCOTXciQIDAQABo1AwTjAdBgNVHQ4EFgQUYRpbQwyD
ahLMN3F2ony3+UqOYOgwHwYDVR0jBBgwFoAUYRpbQwyDahLMN3F2ony3+UqOYOgw
DAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAgEAn9zV7F/XVnFNZhHFrt0Z
S1Yqz+qM9CojLmiyblMFh0p7t+Hh+VKVgMwrz0LwDH4UsOosXA28eJPmech6/bjf
ymkoXISy/NUSTFpUChGO9RabGGxJsT4dugOw9MPaIVZffny4qYOc/rXDXDSfF2b+
303lLPI43y9qoe0oyZ1vtk/UKG75FkWfFUogGNbpOkuz+et5Y0aIEiyg0yh6/l5Q
5h8+yom0HZnREHhqieGbkaGKLkyu7zQ4D4tRK/mBhd8nv+09GtPEG+D5LPbabFVx
KjBMP4Vp24WuSUOqcGSsURHevawPVBfgmsxf1UCjelaIwngdh6WfNCRXa5QQPQTK
ubQvkvXONCDdhmdXQccnRX1nJWhPYi0onffvjsWUfztRypsKzX4dvM9k7xnIcGSG
EnCC4RCgt1UiZIj7frcCMssbA6vJ9naM0s7JF7N3VKeHJtqe1OCRHMYnWUZt9vrq
X6IoIHlZCoLlv39wFW9QNxelcAOCVbD+19MZ0ZXt7LitjIqe7yF5WxDQN4xru087
FzQ4Hfj7eH1SNLLyKZkA1eecjmRoi/OoqAt7afSnwtQLtMUc2bQDg6rHt5C0e4dC
LqP/9PGZTSJiwmtRHJ/N5qYWIh9ju83APvLm/AGBTR2pXmj9G3KdVOkpIC7L35dI
623cSEC3Q3UZutsEm/UplsM=
-----END CERTIFICATE-----
</ca>
key-direction 1
<tls-auth>
#
# 2048 bit OpenVPN static key
#
-----BEGIN OpenVPN Static key V1-----
b02cb1d7c6fee5d4f89b8de72b51a8d0
c7b282631d6fc19be1df6ebae9e2779e
6d9f097058a31c97f57f0c35526a44ae
09a01d1284b50b954d9246725a1ead1f
f224a102ed9ab3da0152a15525643b2e
ee226c37041dc55539d475183b889a10
e18bb94f079a4a49888da566b9978346
0ece01daaf93548beea6c827d9674897
e7279ff1a19cb092659e8c1860fbad0d
b4ad0ad5732f1af4655dbd66214e552f
04ed8fd0104e1d4bf99c249ac229ce16
9d9ba22068c6c0ab742424760911d463
6aafb4b85f0c952a9ce4275bc821391a
a65fcd0d2394f006e3fba0fd34c4bc4a
b260f4b45dec3285875589c97d3087c9
134d3a3aa2f904512e85aa2dc2202498
-----END OpenVPN Static key V1-----
</tls-auth>
EOF
}

# provider_surfshark_get_comp
# comp-lzo is disabled in Surfshark configs.
provider_surfshark_get_comp(){
	printf "no"
}

# provider_surfshark_get_hmac
# key-direction 1 in all Surfshark configs.
provider_surfshark_get_hmac(){
	printf "1"
}

# provider_surfshark_get_short_name hostname addr
# e.g. gb-lon.prod.surfshark.com → GB-LON
provider_surfshark_get_short_name(){
	printf '%s' "$1" | cut -f1 -d '.' | tr 'a-z' 'A-Z'
}

# provider_surfshark_write_certs vpn_no ovpn_detail
# Writes ca + tls-auth (static); removes crl, key, crt.
provider_surfshark_write_certs(){
	_ss_wc_no="$1"
	_ss_wc_ovpn="$2"

	_ss_wc_ca="$(printf '%s' "$_ss_wc_ovpn" | awk '/<ca>/{flag=1;next}/<\/ca>/{flag=0}flag' | sed '/^#/ d')"
	[ -z "$_ss_wc_ca" ] && Print_Output true "Surfshark: Error determining CA certificate" "$ERR" && return 1

	_ss_wc_static="$(printf '%s' "$_ss_wc_ovpn" | awk '/<tls-auth>/{flag=1;next}/<\/tls-auth>/{flag=0}flag' | sed '/^#/ d')"
	[ -z "$_ss_wc_static" ] && Print_Output true "Surfshark: Error determining tls-auth key" "$ERR" && return 1

	printf '%s\n' "$_ss_wc_ca"     > /jffs/openvpn/vpn_crt_client"${_ss_wc_no}"_ca
	printf '%s\n' "$_ss_wc_static" > /jffs/openvpn/vpn_crt_client"${_ss_wc_no}"_static
	rm -f /jffs/openvpn/vpn_crt_client"${_ss_wc_no}"_crl
	rm -f /jffs/openvpn/vpn_crt_client"${_ss_wc_no}"_key
	rm -f /jffs/openvpn/vpn_crt_client"${_ss_wc_no}"_crt
}

# provider_surfshark_get_country_names
# Prints sorted unique country display names, one per line.
provider_surfshark_get_country_names(){
	_ss_cn_data="$SCRIPT_DIR/surfshark_serverdata"
	if [ ! -f "$_ss_cn_data" ]; then
		Print_Output true "Surfshark: Cache missing — run refreshcacheddata" "$ERR"
		return 1
	fi
	jq -r '[.[].country] | unique | sort | .[]' "$_ss_cn_data"
}

# provider_surfshark_get_country_id country_name
# Returns the ISO country code for the given country name.
provider_surfshark_get_country_id(){
	_ss_ci_data="$SCRIPT_DIR/surfshark_serverdata"
	jq -r --arg n "$1" '.[] | select(.country==$n) | .countryCode' "$_ss_ci_data" | head -1
}

# provider_surfshark_get_city_count country_name
provider_surfshark_get_city_count(){
	_ss_cc_data="$SCRIPT_DIR/surfshark_serverdata"
	jq -r --arg n "$1" '[.[] | select(.country==$n) | .location] | unique | length' "$_ss_cc_data"
}

# provider_surfshark_get_city_names country_name
# Returns sorted unique city (location) names for the given country, one per line.
provider_surfshark_get_city_names(){
	_ss_cit_data="$SCRIPT_DIR/surfshark_serverdata"
	jq -r --arg n "$1" '[.[] | select(.country==$n) | .location] | unique | sort | .[]' "$_ss_cit_data"
}

# provider_surfshark_get_city_id country_name city_name
# Surfshark has no separate numeric city ID — the location name is the ID.
provider_surfshark_get_city_id(){
	printf '%s' "$2"
}

# provider_surfshark_country_required
# Returns 1 — country selection is optional.
provider_surfshark_country_required(){
	return 1
}

# provider_surfshark_city_required
# Returns 1 — city selection is optional.
provider_surfshark_city_required(){
	return 1
}

# provider_surfshark_get_types
provider_surfshark_get_types(){
	printf "Standard\n"
}

# provider_surfshark_get_server_load desc
# desc: nvram vpn_clientX_desc value ("Surfshark <hostname_short> Standard UDP")
# Reads load cached by get_server.
provider_surfshark_get_server_load(){
	_ss_sl_desc="$1"
	_ss_sl_short="$(printf '%s' "$_ss_sl_desc" | cut -f2 -d ' ' | tr 'A-Z' 'a-z')"
	_ss_sl_cache="$SCRIPT_DIR/surfshark_load_${_ss_sl_short}"
	if [ -f "$_ss_sl_cache" ]; then
		cat "$_ss_sl_cache"
	else
		printf 'Unknown\n'
	fi
}

# provider_surfshark_needs_cache
# Returns 0 (needs refresh) if cache file is missing, 1 if present.
provider_surfshark_needs_cache(){
	if [ ! -f "$SCRIPT_DIR/surfshark_serverdata" ]; then
		return 0
	fi
	return 1
}
