#!/bin/sh
# Provider: TEMPLATE
# Status: TEMPLATE
# Display: <Provider Full Name>
# Config: <ProviderKey>   (must lowercase to the provider module name, e.g. "NordVPN" → module "nordvpn")
# Description: Copy this file to providers/provider_<name>.sh and implement all functions.
# All functions must be implemented — stubs return error by default.
#
# Naming convention: provider_PROVIDERNAME_FUNCTION
#
# Arguments are positional; providers must not use global state from vpnmgr.sh
# except for SCRIPT_DIR, OVPN_ARCHIVE_DIR, SCRIPT_REPO and Print_Output.
#
# Status values (line 3 of every provider file — read by scripts/provider-test.sh):
#   ACTIVE       — provider is maintained and verified working with a live account
#   API_TESTED   — scripts/api-check.sh passes with --handshake: endpoints, response
#                  contract, generated config and an OpenVPN handshake up to the login
#                  step are verified, and re-checked on a schedule. Not yet connected
#                  with a live account. Requires scripts/api-checks/<name>.sh.
#   UNTESTED     — implementation complete but nothing verified;
#                  API tests still run, failures are expected until confirmed working
#   UNMAINTAINED — provider was functional but is no longer actively maintained;
#                  API tests still run but failures may occur
#   DEPRECATED   — provider service is offline; only static tests run in provider-test.sh
#   TEMPLATE     — not a real provider; provider-test.sh will exit immediately
#
# Rule: any change to a provider resets its status to API_TESTED if the API check
# passes on the pull request, otherwise to UNTESTED. It returns to ACTIVE only once
# the change has been tested end-to-end with a live account on a real router.

##########         Shellcheck directives     ##########
# shellcheck disable=SC2039
# shellcheck disable=SC3043
#######################################################

# provider_template_version
# Prints a version string for this module.
provider_template_version(){
	printf "v0.0.0\n"
}

# provider_template_get_server country_id country_name city_id city_name protocol vpn_type
# Returns a server identifier (hostname or filename stem) on stdout.
# protocol: UDP or TCP
# vpn_type: as returned by provider_template_get_types
provider_template_get_server(){
	Print_Output true "provider_template: get_server not implemented" "$ERR"
	return 1
}

# provider_template_get_ovpn server_id protocol vpn_type
# Downloads/extracts OVPN file contents and prints to stdout.
provider_template_get_ovpn(){
	Print_Output true "provider_template: get_ovpn not implemented" "$ERR"
	return 1
}

# provider_template_get_comp
# Prints the OpenVPN comp-lzo / compress value for this provider.
provider_template_get_comp(){
	printf "no\n"
}

# provider_template_get_hmac
# Prints the HMAC authentication mode value (0/1/2/3).
provider_template_get_hmac(){
	printf "1\n"
}

# provider_template_get_short_name server_id addr
# Returns a short display name derived from server_id and/or addr.
provider_template_get_short_name(){
	Print_Output true "provider_template: get_short_name not implemented" "$ERR"
	return 1
}

# provider_template_get_desc hostname short_name protocol vpn_type
# Prints the nvram vpn_clientX_desc value. Default: reproduce the
# generic format. Override with a provider-specific format if desired
# (see provider_nordvpn.sh for an example using real server metadata).
provider_template_get_desc(){
	printf '%s %s %s %s' "$VPN_PROVIDER" "$2" "$4" "$3"
}

# provider_template_write_certs vpn_no ovpn_detail
# Writes CA/CRL/crt/key/static files to /jffs/openvpn/ for vpn client vpn_no.
# ovpn_detail: full text of the OVPN file (passed as $2)
provider_template_write_certs(){
	Print_Output true "provider_template: write_certs not implemented" "$ERR"
	return 1
}

# provider_template_get_country_names
# Prints a newline-separated list of country names available for this provider.
provider_template_get_country_names(){
	Print_Output true "provider_template: get_country_names not implemented" "$ERR"
	return 1
}

# provider_template_get_country_id country_name
# Prints the numeric country ID for country_name (or "0" if not applicable).
provider_template_get_country_id(){
	printf "0\n"
}

# provider_template_get_city_count country_name
# Prints the number of cities available for country_name.
provider_template_get_city_count(){
	printf "0\n"
}

# provider_template_get_city_names country_name
# Prints a newline-separated list of city names for country_name.
provider_template_get_city_names(){
	Print_Output true "provider_template: get_city_names not implemented" "$ERR"
	return 1
}

# provider_template_get_city_id country_name city_name
# Prints the numeric city ID (or "0" if not applicable).
provider_template_get_city_id(){
	printf "0\n"
}

# provider_template_country_required
# Returns 0 if a country selection is required, 1 if optional.
provider_template_country_required(){
	return 0
}

# provider_template_city_required
# Returns 0 if a city selection is required, 1 if optional.
provider_template_city_required(){
	return 0
}

# provider_template_get_types
# Prints a newline-separated list of VPN type display names.
provider_template_get_types(){
	printf "Standard\n"
}

# provider_template_get_server_load desc
# Prints the current server load percentage string, or "" if unsupported.
# desc: the nvram vpn_clientX_desc value
provider_template_get_server_load(){
	printf ""
}

# provider_template_refresh_cache
# Downloads/updates any cached data files required by this provider.
# Returns 0 on success, 1 on failure.
provider_template_refresh_cache(){
	Print_Output true "provider_template: refresh_cache not implemented" "$ERR"
	return 1
}

# provider_template_needs_cache
# Returns 0 if cached data is missing and a refresh is needed, 1 if cache is present.
provider_template_needs_cache(){
	return 0
}
