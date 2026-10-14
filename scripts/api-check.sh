#!/bin/sh
# api-check.sh
#
# Checks that the external endpoints a provider module depends on still behave
# the way the module expects, by running the UNMODIFIED provider file under
# busybox ash against the live API. Intended to run in an Alpine container
# (see .github/workflows/api-check.yml); it installs a logging shim at
# /usr/sbin/curl and writes cert files to /jffs/openvpn, so it refuses to run
# anywhere else.
#
# Usage:
#   sh scripts/api-check.sh <provider> [--handshake]
#
# Local run (same container as CI):
#   docker run --rm -v "$PWD:/repo:ro" alpine:3.24 sh -c \
#     'apk add -q --no-cache curl jq openssl openvpn && sh /repo/scripts/api-check.sh nordvpn --handshake'
#
# Every provider gets the generic baseline below, which uses only the provider
# function contract. Provider-specific assertions live in
# scripts/api-checks/<provider>.sh (see scripts/api-checks/template.sh).
#
# --handshake additionally starts a real OpenVPN client with fake credentials,
# using the settings vpnmgr.sh would apply to the router, and expects the
# server to reject the login (AUTH_FAILED).
#
# Environment:
#   AC_PROVIDER_FILE   provider file to test instead of providers/provider_<name>.sh
#   AC_RETRY_DELAY     seconds between retries of a failed network check (default 10)
#   AC_FORCE_FAIL      "true" records a failure, to exercise alerting end to end
#   APICHECK_SECRETS   KEY=value lines exported for specs that need credentials
#
# Exit codes:
#   0  all checks passed (or the provider is TEMPLATE/DEPRECATED and was skipped)
#   1  contract broken — an endpoint is gone, rejects the request, or its
#      response no longer has the shape the provider relies on
#   2  inconclusive — failures coincide with rate limiting, blocking, server
#      errors or no response at all
#   3  usage or environment error

##########         Shellcheck directives     ##########
# shellcheck disable=SC2034
# shellcheck disable=SC3043
#######################################################

AC_PROVIDER=""
AC_HANDSHAKE="false"
for _ac_arg in "$@"; do
	case "$_ac_arg" in
		--handshake) AC_HANDSHAKE="true" ;;
		-*)          printf 'Unknown option: %s\n' "$_ac_arg" >&2; exit 3 ;;
		*)           AC_PROVIDER="$_ac_arg" ;;
	esac
done

if [ -z "$AC_PROVIDER" ]; then
	printf 'Usage: sh scripts/api-check.sh <provider> [--handshake]\n' >&2
	exit 3
fi

AC_REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AC_PROVIDER_FILE="${AC_PROVIDER_FILE:-$AC_REPO_ROOT/providers/provider_${AC_PROVIDER}.sh}"
AC_SPEC_FILE="$AC_REPO_ROOT/scripts/api-checks/${AC_PROVIDER}.sh"
AC_RETRY_DELAY="${AC_RETRY_DELAY:-10}"
AC_ATTEMPTS=3

if [ ! -f "$AC_PROVIDER_FILE" ]; then
	printf 'Provider file not found: %s\n' "$AC_PROVIDER_FILE" >&2
	exit 3
fi

AC_STATUS="$(grep '^# Status:' "$AC_PROVIDER_FILE" | head -1 | awk '{print $3}')"

printf '\n[api-check] %s (status: %s)\n\n' "$AC_PROVIDER" "$AC_STATUS"

case "$AC_STATUS" in
	TEMPLATE|DEPRECATED)
		printf '  -  skipped: %s providers are not checked\n\n' "$AC_STATUS"
		exit 0
		;;
esac

# ---------------------------------------------------------------------------
# Environment guard and prerequisites
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ] || { [ ! -f /.dockerenv ] && [ -z "${CI:-}" ]; }; then
	cat >&2 <<EOF
api-check.sh must run as root inside a container. Use:

  docker run --rm -v "\$PWD:/repo:ro" alpine:3.24 sh -c \\
    'apk add -q --no-cache curl jq openssl openvpn && sh /repo/scripts/api-check.sh $AC_PROVIDER'
EOF
	exit 3
fi

for _ac_cmd in curl jq; do
	if ! command -v "$_ac_cmd" >/dev/null 2>&1; then
		printf "'%s' not found — install it first (apk add curl jq)\n" "$_ac_cmd" >&2
		exit 3
	fi
done
if [ "$AC_HANDSHAKE" = "true" ] && ! command -v openvpn >/dev/null 2>&1; then
	printf "'openvpn' not found — install it first (apk add openvpn)\n" >&2
	exit 3
fi

AC_WORK="$(mktemp -d /tmp/vpnmgr_apicheck.XXXXXX)"
trap 'rm -rf "$AC_WORK"' EXIT
AC_HTTP_LOG="$AC_WORK/http.log"
AC_ERR="$AC_WORK/stderr.log"
: > "$AC_HTTP_LOG"
: > "$AC_ERR"
export AC_HTTP_LOG

# ---------------------------------------------------------------------------
# curl shim
# Providers call /usr/sbin/curl (the router binary). The shim runs the real
# curl with the provider's own arguments, untouched, and records the status
# code, size and URL of each request so failures can be classified.
# ---------------------------------------------------------------------------
AC_SHIM_MARK="# vpnmgr api-check curl shim"
AC_REAL_CURL=""
for _ac_c in /usr/bin/curl /bin/curl /usr/local/bin/curl; do
	[ -x "$_ac_c" ] && AC_REAL_CURL="$_ac_c" && break
done
if [ -z "$AC_REAL_CURL" ]; then
	printf 'Could not find a curl binary outside /usr/sbin\n' >&2
	exit 3
fi
if [ -e /usr/sbin/curl ] && ! grep -qF "$AC_SHIM_MARK" /usr/sbin/curl 2>/dev/null; then
	printf '/usr/sbin/curl already exists and is not the api-check shim — refusing to replace it\n' >&2
	exit 3
fi
cat > /usr/sbin/curl <<EOF
#!/bin/sh
$AC_SHIM_MARK
exec $AC_REAL_CURL "\$@" -w '%{stderr}AC_HTTP %{http_code} %{size_download} %{url_effective}\n' 2>>"\${AC_HTTP_LOG:-/dev/null}"
EOF
chmod 0755 /usr/sbin/curl

# ---------------------------------------------------------------------------
# Result tracking
# ---------------------------------------------------------------------------
AC_N_PASS=0
AC_N_SKIP=0
AC_N_WARN=0
AC_N_HARD=0
AC_N_SOFT=0
AC_PENDING_403=""
AC_MSG=""

ac_pass(){
	printf '  ok    %s\n' "$1"
	AC_N_PASS=$((AC_N_PASS + 1))
}

ac_skip(){
	printf '  skip  %s\n' "$1"
	AC_N_SKIP=$((AC_N_SKIP + 1))
}

ac_warn(){
	printf '  warn  %s\n' "$1"
	AC_N_WARN=$((AC_N_WARN + 1))
}

# ac_fail label [hard|soft|soft403:<host>]
# hard = contract broken, soft = inconclusive. Defaults to hard.
# soft403 is inconclusive for now and is settled in the summary, once it is
# known whether <host> answered any other request.
ac_fail(){
	case "${2:-hard}" in
		soft403:*)
			printf '  FAIL  %s  [inconclusive]\n' "$1"
			AC_N_SOFT=$((AC_N_SOFT + 1))
			AC_PENDING_403="$AC_PENDING_403 ${2#soft403:}"
			;;
		soft)
			printf '  FAIL  %s  [inconclusive]\n' "$1"
			AC_N_SOFT=$((AC_N_SOFT + 1))
			;;
		*)
			printf '  FAIL  %s\n' "$1"
			AC_N_HARD=$((AC_N_HARD + 1))
			;;
	esac
}

ac_section(){
	printf '\n%s\n' "$1"
}

# Requests made since log line $1, with query strings removed so that nothing
# passed as a URL parameter is ever printed.
_ac_show_requests(){
	tail -n "+$(($1 + 1))" "$AC_HTTP_LOG" | grep '^AC_HTTP ' \
		| sed 's/?.*$//' | awk '{printf "          http %s  %s bytes  %s\n", $2, $3, $4}'
}

_ac_show_stderr(){
	[ -s "$AC_ERR" ] || return 0
	grep -v '^AC_HTTP ' "$AC_ERR" | sed 's/\x1b\[[0-9;]*m//g' | head -5 | sed 's/^/          /'
}

# Classify a failed attempt from the requests made since log line $1.
# Any 4xx other than auth/rate-limit means the endpoint is gone or rejected the
# request: hard. Otherwise blocking, rate limiting, server errors or no
# response make the result inconclusive: soft. If every request succeeded (or
# none was made) the response itself is wrong: hard.
#
# 403 needs care. It is what a blocked runner sees, but some APIs (NordVPN's
# among them) also answer 403 instead of 404 for a path that no longer exists.
# When 403 is the only problem and the provider uses no credentials, the
# verdict is deferred: see the summary.
_ac_classify(){
	_acc_soft="false"
	_acc_403host=""
	tail -n "+$(($1 + 1))" "$AC_HTTP_LOG" | grep '^AC_HTTP ' > "$AC_WORK/classify"
	while read -r _acc_tag _acc_c _acc_size _acc_url; do
		case "$_acc_c" in
			403)
				_acc_403host="${_acc_url#*://}"
				_acc_403host="${_acc_403host%%[/?:]*}"
				;;
			000|401|407|408|429|5??) _acc_soft="true" ;;
			4??) printf 'hard'; return 0 ;;
		esac
	done < "$AC_WORK/classify"
	if [ "$_acc_soft" = "true" ]; then
		printf 'soft'
	elif [ -n "$_acc_403host" ] && [ -z "${AC_REQUIRED_ENV:-}" ]; then
		printf 'soft403:%s' "$_acc_403host"
	elif [ -n "$_acc_403host" ]; then
		printf 'soft'
	else
		printf 'hard'
	fi
}

# ac_check_net label function [args...]
# Runs a check that talks to the network. A failed check is retried, since a
# 200 response can be transiently empty, which curl --retry does not cover.
# The function may set AC_MSG to add detail to the result line.
ac_check_net(){
	_acn_label="$1"; shift
	_acn_try=1
	while :; do
		_acn_mark="$(wc -l < "$AC_HTTP_LOG" | tr -d ' ')"
		AC_MSG=""
		: > "$AC_ERR"
		if "$@" 2>>"$AC_ERR"; then
			if [ "$_acn_try" -gt 1 ]; then
				ac_pass "${_acn_label}${AC_MSG:+ — $AC_MSG} (attempt $_acn_try)"
			else
				ac_pass "${_acn_label}${AC_MSG:+ — $AC_MSG}"
			fi
			return 0
		fi
		if [ "$_acn_try" -ge "$AC_ATTEMPTS" ]; then
			ac_fail "${_acn_label}${AC_MSG:+ — $AC_MSG}" "$(_ac_classify "$_acn_mark")"
			_ac_show_requests "$_acn_mark"
			_ac_show_stderr
			return 1
		fi
		_acn_try=$((_acn_try + 1))
		sleep "$AC_RETRY_DELAY"
	done
}

# ac_check label function [args...]
# Runs a check that makes no requests. No retry; a failure is a contract break.
ac_check(){
	_ack_label="$1"; shift
	AC_MSG=""
	: > "$AC_ERR"
	if "$@" 2>>"$AC_ERR"; then
		ac_pass "${_ack_label}${AC_MSG:+ — $AC_MSG}"
		return 0
	fi
	ac_fail "${_ack_label}${AC_MSG:+ — $AC_MSG}"
	_ac_show_stderr
	return 1
}

# ac_json label file jq_filter
# Passes when the filter yields a truthy value for the file. A missing or empty
# file is a skip: whatever should have fetched it has already been reported.
ac_json(){
	if [ ! -s "$2" ]; then
		ac_skip "$1 — no data to inspect"
		return 1
	fi
	if jq -e "$3" "$2" >/dev/null 2>&1; then
		ac_pass "$1"
		return 0
	fi
	ac_fail "$1"
	return 1
}

# ac_match label value extended_regex
ac_match(){
	if printf '%s' "$2" | grep -Eq "$3"; then
		ac_pass "$1"
		return 0
	fi
	ac_fail "$1 — got '$2'"
	return 1
}

# ac_size_under label url_substring max_bytes
# Checks the size of the most recent response whose URL contains the substring.
ac_size_under(){
	_asu_size="$(grep '^AC_HTTP 2' "$AC_HTTP_LOG" | grep -F -- "$2" | tail -1 | awk '{print $3}')"
	if [ -z "$_asu_size" ]; then
		ac_skip "$1 — no successful request matched"
		return 1
	fi
	if [ "$_asu_size" -le "$3" ]; then
		ac_pass "$1 — $_asu_size bytes (limit $3)"
		return 0
	fi
	ac_fail "$1 — $_asu_size bytes exceeds limit $3"
	return 1
}

# ac_require_env label
# For specs that need credentials: returns 1 and records a skip when any
# variable named in AC_REQUIRED_ENV is unset, so the calling check can bail out.
ac_require_env(){
	for _are_name in ${AC_REQUIRED_ENV:-}; do
		eval "_are_val=\"\${$_are_name:-}\""
		if [ -z "$_are_val" ]; then
			ac_skip "$1 — skipped (no credentials: $_are_name)"
			return 1
		fi
	done
	return 0
}

# ac_get_server label country_id country_name city_id city_name protocol vpn_type
# Sets AC_SERVER to the provider's chosen server, or to "" on failure.
ac_get_server(){
	_ags_label="$1"; shift
	AC_SERVER=""
	ac_check_net "$_ags_label" _ac_do_get_server "$@"
}

_ac_do_get_server(){
	AC_SERVER="$("provider_${AC_PROVIDER}_get_server" "$@")"
	[ -n "$AC_SERVER" ] || return 1
	AC_MSG="$AC_SERVER"
}

# ---------------------------------------------------------------------------
# Credentials for specs that need them
# ---------------------------------------------------------------------------
if [ -n "${APICHECK_SECRETS:-}" ]; then
	while IFS= read -r _ac_line; do
		case "$_ac_line" in
			''|'#'*) continue ;;
			*=*) ;;
			*) continue ;;
		esac
		_ac_key="${_ac_line%%=*}"
		_ac_val="${_ac_line#*=}"
		case "$_ac_key" in
			''|[0-9]*|*[!A-Za-z0-9_]*) continue ;;
		esac
		[ -n "${GITHUB_ACTIONS:-}" ] && [ -n "$_ac_val" ] && printf '::add-mask::%s\n' "$_ac_val"
		export "$_ac_key=$_ac_val"
	done <<EOF
$APICHECK_SECRETS
EOF
fi

# ---------------------------------------------------------------------------
# Router environment stubs
# ---------------------------------------------------------------------------
SCRIPT_DIR="$AC_WORK/vpnmgr.d"
OVPN_ARCHIVE_DIR="$SCRIPT_DIR/ovpn"
SCRIPT_REPO="https://raw.githubusercontent.com/h0me5k1n/vpnmgr/main"
VPN_PROVIDER="$(grep '^# Config:' "$AC_PROVIDER_FILE" | head -1 | awk '{print $3}')"
PASS=""; WARN=""; ERR=""; CRIT=""; BOLD=""; CLEARFORMAT=""

Print_Output(){ printf '%s\n' "$2" >&2; }
Download_File(){ /usr/sbin/curl -fsL --retry 3 "$1" -o "$2"; }
Create_Symlinks(){ :; }

mkdir -p "$SCRIPT_DIR" "$OVPN_ARCHIVE_DIR" /jffs/openvpn

# The OVPN parsers and the cipher list are taken from vpnmgr.sh itself so the
# provider's output is judged by the code the router runs.
for _ac_fn in getIP getPort getCipher getAuthDigest getClientCA; do
	sed -n "/^${_ac_fn}(){/,/^}/p" "$AC_REPO_ROOT/vpnmgr.sh"
done > "$AC_WORK/core_parsers.sh"
# shellcheck source=/dev/null
. "$AC_WORK/core_parsers.sh"
AC_NCP_CIPHERS="$(grep -m1 '_ncp_ciphers=' "$AC_REPO_ROOT/vpnmgr.sh" | sed 's/.*_ncp_ciphers="\([^"]*\)".*/\1/')"

# shellcheck source=/dev/null
. "$AC_PROVIDER_FILE"

AC_REQUIRED_ENV=""
AC_COUNTRY=""
if [ -f "$AC_SPEC_FILE" ]; then
	# shellcheck source=/dev/null
	. "$AC_SPEC_FILE"
fi

# ---------------------------------------------------------------------------
# Baseline check functions
# ---------------------------------------------------------------------------
_ac_refresh_cache(){
	"provider_${AC_PROVIDER}_refresh_cache" >/dev/null
}

_ac_country_names(){
	AC_COUNTRY_NAMES="$("provider_${AC_PROVIDER}_get_country_names")"
	[ -n "$AC_COUNTRY_NAMES" ] || return 1
	AC_MSG="$(printf '%s\n' "$AC_COUNTRY_NAMES" | wc -l | tr -d ' ') countries"
}

_ac_country_id(){
	AC_COUNTRY_ID="$("provider_${AC_PROVIDER}_get_country_id" "$AC_COUNTRY")"
	[ -n "$AC_COUNTRY_ID" ] || return 1
	AC_MSG="$AC_COUNTRY_ID"
}

_ac_city_names(){
	AC_CITY_NAMES="$("provider_${AC_PROVIDER}_get_city_names" "$AC_COUNTRY")"
	[ -n "$AC_CITY_NAMES" ] || return 1
	AC_CITY="$(printf '%s\n' "$AC_CITY_NAMES" | head -1)"
	_accn_count="$("provider_${AC_PROVIDER}_get_city_count" "$AC_COUNTRY")"
	_accn_listed="$(printf '%s\n' "$AC_CITY_NAMES" | wc -l | tr -d ' ')"
	AC_MSG="$_accn_listed cities, get_city_count says $_accn_count"
	[ "$_accn_count" = "$_accn_listed" ]
}

_ac_city_id(){
	AC_CITY_ID="$("provider_${AC_PROVIDER}_get_city_id" "$AC_COUNTRY" "$AC_CITY")"
	[ -n "$AC_CITY_ID" ] || return 1
	AC_MSG="$AC_CITY → $AC_CITY_ID"
}

_ac_static_value(){
	_acs_val="$("provider_${AC_PROVIDER}_$1")" || return 1
	AC_MSG="'$_acs_val'"
	printf '%s' "$_acs_val" | grep -Eq "$2"
}

_ac_types(){
	AC_TYPES="$("provider_${AC_PROVIDER}_get_types")"
	[ -n "$AC_TYPES" ] || return 1
	AC_TYPE="$(printf '%s\n' "$AC_TYPES" | head -1)"
	AC_MSG="$(printf '%s' "$AC_TYPES" | tr '\n' ',' | sed 's/,$//')"
}

_ac_get_ovpn(){
	AC_OVPN="$("provider_${AC_PROVIDER}_get_ovpn" "$AC_SERVER" "$1" "$AC_TYPE")"
	[ -n "$AC_OVPN" ] || return 1
	AC_MSG="${#AC_OVPN} bytes"
}

# The same five extractions UpdateVPNConfig() performs; it aborts if any is empty.
_ac_parse_ovpn(){
	AC_OVPN_ADDR="$(getIP "$AC_OVPN")"
	AC_OVPN_PORT="$(getPort "$AC_OVPN")"
	AC_OVPN_CIPHER="$(getCipher "$AC_OVPN")"
	AC_OVPN_DIGEST="$(getAuthDigest "$AC_OVPN")"
	_acp_ca="$(getClientCA "$AC_OVPN")"
	AC_MSG="remote=$AC_OVPN_ADDR port=$AC_OVPN_PORT cipher=$AC_OVPN_CIPHER auth=$AC_OVPN_DIGEST"
	[ -n "$AC_OVPN_ADDR" ] && [ -n "$AC_OVPN_PORT" ] && [ -n "$AC_OVPN_CIPHER" ] \
		&& [ -n "$AC_OVPN_DIGEST" ] && [ -n "$_acp_ca" ] || return 1
	printf '%s' "$AC_OVPN_PORT" | grep -Eq '^[0-9]+$'
}

_ac_write_certs(){
	rm -f /jffs/openvpn/vpn_crt_client1_*
	"provider_${AC_PROVIDER}_write_certs" 1 "$AC_OVPN" || return 1
	grep -q 'BEGIN CERTIFICATE' /jffs/openvpn/vpn_crt_client1_ca 2>/dev/null || return 1
	AC_MSG="wrote$(for _acw_f in /jffs/openvpn/vpn_crt_client1_*; do printf ' %s' "${_acw_f##*_}"; done)"
}

# Embedded CA certificates expire without any API changing.
_ac_ca_validity(){
	_acv_end="$(openssl x509 -in /jffs/openvpn/vpn_crt_client1_ca -noout -enddate 2>/dev/null | cut -f2 -d'=')"
	[ -n "$_acv_end" ] || { AC_MSG="not a parseable certificate"; return 1; }
	AC_MSG="expires $_acv_end"
	openssl x509 -in /jffs/openvpn/vpn_crt_client1_ca -noout -checkend 0 >/dev/null 2>&1
}

_ac_desc(){
	_acd_short="$("provider_${AC_PROVIDER}_get_short_name" "$AC_SERVER" "$AC_OVPN_ADDR")"
	_acd_desc="$("provider_${AC_PROVIDER}_get_desc" "$AC_SERVER" "$_acd_short" "$1" "$AC_TYPE")"
	[ -n "$_acd_short" ] && [ -n "$_acd_desc" ] || return 1
	"provider_${AC_PROVIDER}_get_server_load" "$_acd_desc" >/dev/null || return 1
	AC_MSG="'$_acd_desc'"
}

# ---------------------------------------------------------------------------
# Handshake probe
# Builds a client config from the values vpnmgr.sh stores in nvram
# (UpdateVPNConfig) plus the cert files write_certs produced, in the way the
# firmware turns those into an OpenVPN config, then connects with fake
# credentials. Reaching AUTH_FAILED proves the address, port, protocol, CA,
# and tls-auth key/direction/digest. It does not prove the data cipher, which
# is only negotiated after a successful login.
# ---------------------------------------------------------------------------
_ac_handshake(){
	_ach_prot="$1"
	_ach_conf="$AC_WORK/probe_${_ach_prot}.conf"
	_ach_log="$AC_WORK/probe_${_ach_prot}.log"
	_ach_hmac="$("provider_${AC_PROVIDER}_get_hmac")"
	_ach_static="/jffs/openvpn/vpn_crt_client1_static"
	AC_HS_RESULT=""

	printf 'vpnmgr-api-check\nnot-a-real-login\n' > "$AC_WORK/probe_up"
	chmod 0600 "$AC_WORK/probe_up"

	{
		printf 'client\ndev null\nnobind\n'
		if [ "$_ach_prot" = "TCP" ]; then printf 'proto tcp-client\n'; else printf 'proto udp\n'; fi
		printf 'remote %s %s\n' "$AC_OVPN_ADDR" "$AC_OVPN_PORT"
		printf 'auth %s\n' "$AC_OVPN_DIGEST"
		printf 'data-ciphers %s\n' "$AC_NCP_CIPHERS"
		printf 'data-ciphers-fallback %s\n' "$AC_OVPN_CIPHER"
		printf 'ca /jffs/openvpn/vpn_crt_client1_ca\n'
		if [ -s "$_ach_static" ]; then
			case "$_ach_hmac" in
				0|1) printf 'tls-auth %s %s\n' "$_ach_static" "$_ach_hmac" ;;
				2)   printf 'tls-auth %s\n' "$_ach_static" ;;
				3)   printf 'tls-crypt %s\n' "$_ach_static" ;;
			esac
		fi
		[ -s /jffs/openvpn/vpn_crt_client1_crl ] && printf 'crl-verify /jffs/openvpn/vpn_crt_client1_crl\n'
		printf 'remote-cert-tls server\n'
		printf 'auth-user-pass %s\nauth-retry none\nauth-nocache\n' "$AC_WORK/probe_up"
		printf 'connect-retry-max 1\nconnect-timeout 15\nserver-poll-timeout 15\nhand-window 20\n'
		printf 'resolv-retry 5\nverb 3\n'
	} > "$_ach_conf"

	timeout 60 openvpn --config "$_ach_conf" > "$_ach_log" 2>&1

	if grep -q 'AUTH_FAILED' "$_ach_log"; then
		AC_HS_RESULT="pass"
	elif grep -q 'Initialization Sequence Completed' "$_ach_log"; then
		AC_HS_RESULT="hard"
		AC_MSG="server accepted fake credentials"
	elif grep -Eq 'VERIFY ERROR|certificate verify failed|CRL has expired|Options error|Cannot load|cipher .* not supported|TLS Error: tls-(auth|crypt)|HMAC authentication failed' "$_ach_log"; then
		AC_HS_RESULT="hard"
		AC_MSG="$(grep -E 'VERIFY ERROR|certificate verify failed|CRL has expired|Options error|Cannot load|not supported|TLS Error|HMAC authentication failed' "$_ach_log" | head -1 | sed 's/^[0-9: -]*//')"
	elif [ "$_ach_prot" = "TCP" ] && grep -q 'TCP connection established' "$_ach_log"; then
		# The server accepted the TCP connection and then ignored the TLS
		# handshake, which is what a wrong tls-auth key, direction or digest
		# looks like. Over UDP the same fault is indistinguishable from a
		# blocked path, so only TCP can report it.
		AC_HS_RESULT="hard"
		AC_MSG="server reachable but did not answer the TLS handshake"
	else
		AC_HS_RESULT="soft"
		AC_MSG="no response from server"
	fi
}

_ac_show_probe_log(){
	grep -Ev '^[0-9: -]*(NOTE|WARNING|DEPRECAT|OpenVPN |library versions|DCO )' "$AC_WORK/probe_$1.log" \
		| sed 's/^[0-9]\{4\}-[0-9-]* [0-9:]* //' | tail -6 | sed 's/^/          /'
}

# Runs the probe for one protocol and records the result.
ac_handshake(){
	_ah_prot="$1"
	AC_MSG=""
	_ac_handshake "$_ah_prot"
	if [ "$AC_HS_RESULT" != "pass" ]; then
		sleep "$AC_RETRY_DELAY"
		_ac_handshake "$_ah_prot"
	fi
	eval "AC_HS_$_ah_prot=\"\$AC_HS_RESULT\""
	case "$AC_HS_RESULT" in
		pass) ac_pass "handshake $_ah_prot — reached AUTH_FAILED at $AC_OVPN_ADDR:$AC_OVPN_PORT" ;;
		hard) ac_fail "handshake $_ah_prot — $AC_MSG"; _ac_show_probe_log "$_ah_prot" ;;
		soft) ac_fail "handshake $_ah_prot — $AC_MSG" soft; _ac_show_probe_log "$_ah_prot" ;;
	esac
}

# ---------------------------------------------------------------------------
# Baseline — every provider
# ---------------------------------------------------------------------------
ac_section "Static functions"
ac_check "version" _ac_static_value version '.'
ac_check "get_types" _ac_types
ac_check "get_comp is a value the firmware accepts" _ac_static_value get_comp '^(-1|no|yes|adaptive|lz4|lz4-v2)$'
ac_check "get_hmac is a value the firmware accepts" _ac_static_value get_hmac '^(-1|0|1|2|3|4)?$'

ac_section "Server data"
AC_COUNTRY_NAMES=""; AC_COUNTRY_ID=""; AC_CITY=""; AC_CITY_ID=""
if ac_check_net "refresh_cache" _ac_refresh_cache; then
	if ac_check "get_country_names" _ac_country_names; then
		# Prefer a stable, well-served country; fall back to whatever is listed first.
		if [ -z "$AC_COUNTRY" ] || ! printf '%s\n' "$AC_COUNTRY_NAMES" | grep -qxF "$AC_COUNTRY"; then
			if printf '%s\n' "$AC_COUNTRY_NAMES" | grep -qxF "United Kingdom"; then
				AC_COUNTRY="United Kingdom"
			else
				AC_COUNTRY="$(printf '%s\n' "$AC_COUNTRY_NAMES" | head -1)"
			fi
		fi
		ac_check "get_country_id '$AC_COUNTRY'" _ac_country_id
		if ac_check "get_city_names '$AC_COUNTRY'" _ac_city_names; then
			ac_check "get_city_id" _ac_city_id
		fi
	fi
else
	ac_skip "country and city lookups — no server data"
fi

AC_HS_UDP=""; AC_HS_TCP=""
for AC_PROT in UDP TCP; do
	ac_section "Server selection and config — $AC_PROT"
	if [ -z "$AC_COUNTRY_ID" ]; then
		ac_skip "get_server $AC_PROT — no country to select"
		continue
	fi
	if "provider_${AC_PROVIDER}_city_required"; then
		ac_get_server "get_server $AC_COUNTRY / $AC_CITY $AC_PROT $AC_TYPE" \
			"$AC_COUNTRY_ID" "$AC_COUNTRY" "$AC_CITY_ID" "$AC_CITY" "$AC_PROT" "$AC_TYPE"
	else
		ac_get_server "get_server $AC_COUNTRY $AC_PROT $AC_TYPE" \
			"$AC_COUNTRY_ID" "$AC_COUNTRY" "0" "" "$AC_PROT" "$AC_TYPE"
	fi
	if [ -z "$AC_SERVER" ]; then
		ac_skip "get_ovpn $AC_PROT — no server selected"
		continue
	fi
	if ! ac_check_net "get_ovpn" _ac_get_ovpn "$AC_PROT"; then
		continue
	fi
	ac_check "OVPN parses with vpnmgr.sh getIP/getPort/getCipher/getAuthDigest/getClientCA" _ac_parse_ovpn || continue
	ac_check "get_short_name / get_desc / get_server_load" _ac_desc "$AC_PROT"
	ac_check "write_certs" _ac_write_certs || continue
	if command -v openssl >/dev/null 2>&1; then
		ac_check "CA certificate is valid" _ac_ca_validity
	fi
	_ac_hmac_now="$("provider_${AC_PROVIDER}_get_hmac")"
	case "$_ac_hmac_now" in
		0|1|2|3|4)
			[ -s /jffs/openvpn/vpn_crt_client1_static ] \
				|| ac_warn "get_hmac returns '$_ac_hmac_now' but write_certs wrote no static key"
			;;
	esac
	if [ "$AC_HANDSHAKE" = "true" ]; then
		ac_handshake "$AC_PROT"
	fi
done

# ---------------------------------------------------------------------------
# Provider-specific checks
# ---------------------------------------------------------------------------
if command -v "api_check_${AC_PROVIDER}" >/dev/null 2>&1; then
	ac_section "Provider-specific checks"
	"api_check_${AC_PROVIDER}"
else
	ac_section "Provider-specific checks"
	ac_warn "no scripts/api-checks/${AC_PROVIDER}.sh — baseline only"
fi

if [ "${AC_FORCE_FAIL:-}" = "true" ]; then
	ac_section "Forced failure"
	ac_fail "AC_FORCE_FAIL is set — this failure is deliberate, to test alerting"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
# A 403 from a host that answered other requests normally in this run is not
# the runner being blocked; the endpoint itself is being refused.
for _ac_host in $AC_PENDING_403; do
	if grep -Eq "^AC_HTTP 2[0-9][0-9] [0-9]+ https?://${_ac_host}[/:?]" "$AC_HTTP_LOG"; then
		AC_N_SOFT=$((AC_N_SOFT - 1))
		AC_N_HARD=$((AC_N_HARD + 1))
		printf '\n  note  403 from %s while other requests to it succeeded — counted as a broken contract\n' "$_ac_host"
	fi
done

printf '\n-----------------------------------------\n'
printf '%s passed, %s failed, %s inconclusive, %s skipped, %s warnings\n' \
	"$AC_N_PASS" "$AC_N_HARD" "$AC_N_SOFT" "$AC_N_SKIP" "$AC_N_WARN"

if [ "$AC_N_HARD" -gt 0 ]; then
	printf 'RESULT: CONTRACT BROKEN — %s needs attention\n\n' "$AC_PROVIDER"
	exit 1
elif [ "$AC_N_SOFT" -gt 0 ]; then
	printf 'RESULT: INCONCLUSIVE — could not get a clean answer from the provider\n\n'
	exit 2
fi
printf 'RESULT: OK\n\n'
exit 0
