#!/bin/sh
# API checks specific to the Surfshark provider.
# Sourced by scripts/api-check.sh after the provider module; see template.sh
# for the helpers available here.
#
# Endpoint provider_surfshark.sh depends on:
#   https://api.surfshark.com/v4/server/clusters   (refresh_cache)
# The OVPN config is built by the provider, with an embedded CA certificate
# and tls-auth key.

##########         Shellcheck directives     ##########
# shellcheck disable=SC2034
# shellcheck disable=SC2154
#######################################################

AC_COUNTRY="United Kingdom"

api_check_surfshark(){
	_acs_data="$SCRIPT_DIR/surfshark_serverdata"

	ac_json "clusters: array of more than 50 entries" "$_acs_data" \
		'type=="array" and length > 50'
	ac_json "clusters: every entry has connectionName, country, countryCode and location" "$_acs_data" \
		'all(.[]; (.connectionName|type)=="string" and (.country|type)=="string" and (.countryCode|type)=="string" and (.location|type)=="string")'
	ac_json "clusters: every entry has a numeric load" "$_acs_data" \
		'all(.[]; (.load|type)=="number")'

	# No location filter: the provider falls back to the least loaded server anywhere.
	ac_get_server "least loaded server worldwide" 0 "" 0 "" UDP Standard
}
