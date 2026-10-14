#!/bin/sh
# API checks specific to the NordVPN provider.
# Sourced by scripts/api-check.sh after the provider module; see template.sh
# for the helpers available here.
#
# Endpoints provider_nordvpn.sh depends on:
#   https://api.nordvpn.com/v1/servers/countries         (refresh_cache)
#   https://api.nordvpn.com/v1/servers/recommendations   (get_server)
#   https://downloads.nordcdn.com/configs/files/...      (get_ovpn)
# The <ca> and <tls-auth> blocks of the downloaded config are covered by the
# baseline, since provider_nordvpn_write_certs fails without either.

##########         Shellcheck directives     ##########
# shellcheck disable=SC2034
# shellcheck disable=SC2154
#######################################################

AC_COUNTRY="United Kingdom"

# get_server caches the load and location of the server it picked; get_desc
# and get_server_load depend on both files.
_ac_nordvpn_selection(){
	_ans_short="${AC_SERVER%%.*}"
	_ans_load="$(cat "$SCRIPT_DIR/nordvpn_load_${_ans_short}" 2>/dev/null)"
	_ans_meta="$(cat "$SCRIPT_DIR/nordvpn_meta_${_ans_short}" 2>/dev/null)"
	_ans_country="$(printf '%s' "$_ans_meta" | cut -f1 -d'|')"
	_ans_code="$(printf '%s' "$_ans_meta" | cut -f2 -d'|')"
	AC_NORDVPN_CITY="$(printf '%s' "$_ans_meta" | cut -f3 -d'|')"
	AC_MSG="load=$_ans_load location=$_ans_meta"
	printf '%s' "$AC_SERVER" | grep -Eq '^[a-z0-9-]+\.nordvpn\.com$' || return 1
	printf '%s' "$_ans_load" | grep -Eq '^[0-9]+$' || return 1
	[ -n "$_ans_country" ] && [ -n "$_ans_code" ] && [ -n "$AC_NORDVPN_CITY" ]
}

_ac_nordvpn_city_matches(){
	AC_MSG="asked for $1, got $AC_NORDVPN_CITY"
	[ "$AC_NORDVPN_CITY" = "$1" ]
}

_ac_nordvpn_fetch_groups(){
	/usr/sbin/curl -fsL --retry 3 "https://api.nordvpn.com/v1/servers/groups" > "$AC_WORK/nordvpn_groups"
	jq -e 'type=="array" and length > 0' "$AC_WORK/nordvpn_groups" >/dev/null
}

api_check_nordvpn(){
	_acn_data="$SCRIPT_DIR/nordvpn_countrydata"

	ac_json "countries: array of more than 50 entries" "$_acn_data" \
		'type=="array" and length > 50'
	ac_json "countries: every entry has a numeric id and a name" "$_acn_data" \
		'all(.[]; (.id|type)=="number" and (.name|type)=="string")'
	ac_json "countries: every city has a numeric id and a name" "$_acn_data" \
		'all(.[]; (.cities|type)=="array" and all(.cities[]; (.id|type)=="number" and (.name|type)=="string"))'

	# Every type the provider offers, over both protocols, with no location filter.
	for _acn_type in $(provider_nordvpn_get_types); do
		for _acn_prot in UDP TCP; do
			if ac_get_server "recommendations: worldwide $_acn_type $_acn_prot" \
				0 "" 0 "" "$_acn_prot" "$_acn_type"; then
				ac_check "  load and location cached" _ac_nordvpn_selection
			fi
		done
	done

	# City lookup. Use the country's best-served city so that an empty result
	# means the query broke, not that the city has no servers of this type.
	_acn_city="$(jq -r --arg c "$AC_COUNTRY" \
		'.[] | select(.name==$c) | .cities | (max_by(.serverCount // 0) // .[0]) | .name // empty' \
		"$_acn_data" 2>/dev/null)"
	if [ -n "$_acn_city" ] && [ -n "$AC_COUNTRY_ID" ]; then
		_acn_cityid="$(provider_nordvpn_get_city_id "$AC_COUNTRY" "$_acn_city")"
		if ac_get_server "recommendations: $AC_COUNTRY / $_acn_city UDP Standard" \
			"$AC_COUNTRY_ID" "$AC_COUNTRY" "$_acn_cityid" "$_acn_city" UDP Standard; then
			ac_check "  load and location cached" _ac_nordvpn_selection \
				&& ac_check "  city filter honoured" _ac_nordvpn_city_matches "$_acn_city"
		fi
		# The city lookup downloads every server in the country and filters it
		# with jq on the router, so its size matters.
		ac_size_under "city lookup response size" "limit=2500" 5000000
	else
		ac_skip "city lookup — no country data"
	fi

	# The group identifiers the provider sends must still exist.
	if ac_check_net "groups list" _ac_nordvpn_fetch_groups; then
		for _acn_type in $(provider_nordvpn_get_types); do
			_acn_group="$(_nordvpn_type_to_api "$_acn_type")"
			ac_json "group '$_acn_group' ($_acn_type) exists" "$AC_WORK/nordvpn_groups" \
				"any(.[]; .identifier==\"$_acn_group\")"
		done
	fi
}
