#!/bin/sh
# API checks specific to the PIA provider.
# Sourced by scripts/api-check.sh after the provider module; see template.sh
# for the helpers available here.
#
# Endpoints provider_pia.sh depends on:
#   https://serverlist.piaservers.net/vpninfo/servers/v6            (refresh_cache)
#   https://www.privateinternetaccess.com/openvpn/crl.rsa.2048.pem  (refresh_cache)
# The OVPN config is built by the provider, with an embedded CA certificate.

##########         Shellcheck directives     ##########
# shellcheck disable=SC2034
# shellcheck disable=SC2154
#######################################################

AC_COUNTRY="United Kingdom"

# refresh_cache carries on without the CRL, so its absence has to be caught here.
_ac_pia_crl(){
	grep -q 'BEGIN X509 CRL' "$SCRIPT_DIR/pia_crl.pem" 2>/dev/null
}

# Country codes with no entry in _pia_country_name() are shown to the user as
# a bare two-letter code.
_ac_pia_unmapped(){
	_apu_missing=""
	for _apu_code in $(jq -r '[.regions[].country] | unique | .[]' "$SCRIPT_DIR/pia_serverdata"); do
		[ "$(_pia_country_name "$_apu_code")" = "$_apu_code" ] && _apu_missing="$_apu_missing $_apu_code"
	done
	AC_MSG="${_apu_missing# }"
	[ -z "$_apu_missing" ]
}

_ac_pia_strong(){
	_aps_ovpn="$(provider_pia_get_ovpn "$AC_SERVER" UDP Strong)"
	AC_MSG="cipher=$(getCipher "$_aps_ovpn") auth=$(getAuthDigest "$_aps_ovpn")"
	[ -n "$(getIP "$_aps_ovpn")" ] && [ -n "$(getCipher "$_aps_ovpn")" ] && [ -n "$(getAuthDigest "$_aps_ovpn")" ]
}

api_check_pia(){
	_acp_data="$SCRIPT_DIR/pia_serverdata"

	ac_json "server list: more than 20 regions" "$_acp_data" \
		'(.regions|type)=="array" and (.regions|length) > 20'
	ac_json "server list: every region has id, name, country and dns" "$_acp_data" \
		'all(.regions[]; (.id|type)=="string" and (.name|type)=="string" and (.country|type)=="string" and (.dns|type)=="string")'
	ac_json "server list: every region has a boolean offline flag" "$_acp_data" \
		'all(.regions[]; (.offline|type)=="boolean")'
	ac_json "server list: at least one region is online" "$_acp_data" \
		'any(.regions[]; .offline==false)'

	ac_check "CRL downloaded and is a PEM CRL" _ac_pia_crl

	if [ -s "$_acp_data" ]; then
		_ac_pia_unmapped || ac_warn "country codes with no display name in _pia_country_name: $AC_MSG"
	fi

	if [ -n "$AC_SERVER" ]; then
		ac_check "Strong type config parses" _ac_pia_strong
	fi
}
