#!/bin/sh
# API checks specific to the <name> provider.
#
# Copy to scripts/api-checks/<name>.sh and rename api_check_template to
# api_check_<name>. scripts/api-check.sh sources this file after the provider
# module, runs its generic baseline (refresh_cache, country and city lookups,
# get_server, get_ovpn, write_certs and, with --handshake, an OpenVPN login
# attempt), then calls api_check_<name>.
#
# Put here what the baseline cannot know: the fields this provider reads from
# each response, and any selection paths beyond "one country, first type".
# A provider needs this file before its status can be API_TESTED or ACTIVE.
#
# Available from api-check.sh:
#   SCRIPT_DIR            cache directory the provider wrote to
#   AC_WORK               scratch directory, removed on exit
#   AC_COUNTRY, AC_COUNTRY_ID, AC_CITY, AC_CITY_ID
#                         location the baseline used
#   AC_SERVER             server returned by the last ac_get_server
#   getIP getPort getCipher getAuthDigest getClientCA
#                         the OVPN parsers from vpnmgr.sh
#
#   ac_json label file jq_filter
#       Pass when the jq filter is truthy for the file.
#   ac_match label value extended_regex
#   ac_size_under label url_substring max_bytes
#       Size of the latest response whose URL contains the substring.
#   ac_get_server label country_id country_name city_id city_name protocol type
#       Calls provider_<name>_get_server with retries; sets AC_SERVER.
#   ac_check_net label function [args...]
#       Runs a function that makes requests, retrying on failure. HTTP status
#       codes decide whether a failure is a broken contract or inconclusive.
#   ac_check label function [args...]
#       Runs a function that makes no requests. A failure is a broken contract.
#       Functions return 0/1 and may set AC_MSG to add detail.
#   ac_pass / ac_fail [hard|soft] / ac_warn / ac_skip label
#
# Credentials: if any check needs an account or API token, name the variables
# in AC_REQUIRED_ENV and guard those checks with ac_require_env. In CI the
# values come from one repository secret named APICHECK_<NAME> holding
# KEY=value lines. Without them (always the case for pull requests from
# forks) the guarded checks are skipped and everything else still runs.

##########         Shellcheck directives     ##########
# shellcheck disable=SC2034
# shellcheck disable=SC2154
#######################################################

# Country the baseline should use, if listed. Defaults to United Kingdom, then
# to the first country the provider returns.
AC_COUNTRY="United Kingdom"

# AC_REQUIRED_ENV="TEMPLATE_TOKEN"

# _ac_template_account(){
# 	/usr/sbin/curl -fsL --retry 3 -H "Authorization: Bearer $TEMPLATE_TOKEN" \
# 		"https://api.example.com/v1/account" > "$AC_WORK/template_account"
# }

api_check_template(){
	_act_data="$SCRIPT_DIR/template_serverdata"

	ac_json "server list: non-empty array" "$_act_data" \
		'type=="array" and length > 0'
	ac_json "server list: every entry has the fields the provider reads" "$_act_data" \
		'all(.[]; (.hostname|type)=="string" and (.country|type)=="string")'

	# if ac_require_env "account endpoint"; then
	# 	ac_check_net "account endpoint" _ac_template_account
	# fi
}
