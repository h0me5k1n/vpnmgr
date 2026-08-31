#!/bin/sh
# PIA (Private Internet Access) provider module for vpnmgr
# Status: UNTESTED — rewritten to use PIA JSON API; not yet verified on a live account
# Display: Private Internet Access (PIA)
# Config: PIA
#
# Depends on: jq, curl
# Cache files: $SCRIPT_DIR/pia_serverdata  (JSON from serverlist.piaservers.net)
#              $SCRIPT_DIR/pia_crl.pem     (CRL from privateinternetaccess.com)
#
# Status values (line 3 of every provider file — read by scripts/provider-test.sh):
#   ACTIVE       — provider is maintained and its API is operational
#   UNMAINTAINED — provider was functional but is no longer actively maintained
#   DEPRECATED   — provider service is offline; only static tests run
#   TEMPLATE     — not a real provider; provider-test.sh will exit immediately

##########         Shellcheck directives     ##########
# shellcheck disable=SC2039
# shellcheck disable=SC3043
#######################################################

provider_pia_version(){
	printf "v2.0.0\n"
}

# Internal: map ISO-3166-1 alpha-2 code → display name for all 91 PIA countries.
_pia_country_name(){
	case "$1" in
		AD) printf "Andorra" ;;
		AE) printf "United Arab Emirates" ;;
		AL) printf "Albania" ;;
		AM) printf "Armenia" ;;
		AR) printf "Argentina" ;;
		AT) printf "Austria" ;;
		AU) printf "Australia" ;;
		BA) printf "Bosnia and Herzegovina" ;;
		BD) printf "Bangladesh" ;;
		BE) printf "Belgium" ;;
		BG) printf "Bulgaria" ;;
		BO) printf "Bolivia" ;;
		BR) printf "Brazil" ;;
		BS) printf "Bahamas" ;;
		CA) printf "Canada" ;;
		CH) printf "Switzerland" ;;
		CL) printf "Chile" ;;
		CN) printf "China" ;;
		CO) printf "Colombia" ;;
		CR) printf "Costa Rica" ;;
		CY) printf "Cyprus" ;;
		CZ) printf "Czech Republic" ;;
		DE) printf "Germany" ;;
		DK) printf "Denmark" ;;
		DZ) printf "Algeria" ;;
		EC) printf "Ecuador" ;;
		EE) printf "Estonia" ;;
		EG) printf "Egypt" ;;
		ES) printf "Spain" ;;
		FI) printf "Finland" ;;
		FR) printf "France" ;;
		GB) printf "United Kingdom" ;;
		GE) printf "Georgia" ;;
		GL) printf "Greenland" ;;
		GR) printf "Greece" ;;
		GT) printf "Guatemala" ;;
		HK) printf "Hong Kong" ;;
		HR) printf "Croatia" ;;
		HU) printf "Hungary" ;;
		ID) printf "Indonesia" ;;
		IE) printf "Ireland" ;;
		IL) printf "Israel" ;;
		IM) printf "Isle of Man" ;;
		IN) printf "India" ;;
		IS) printf "Iceland" ;;
		IT) printf "Italy" ;;
		JP) printf "Japan" ;;
		KH) printf "Cambodia" ;;
		KR) printf "South Korea" ;;
		KZ) printf "Kazakhstan" ;;
		LI) printf "Liechtenstein" ;;
		LK) printf "Sri Lanka" ;;
		LT) printf "Lithuania" ;;
		LU) printf "Luxembourg" ;;
		LV) printf "Latvia" ;;
		MA) printf "Morocco" ;;
		MC) printf "Monaco" ;;
		MD) printf "Moldova" ;;
		ME) printf "Montenegro" ;;
		MK) printf "North Macedonia" ;;
		MN) printf "Mongolia" ;;
		MO) printf "Macao" ;;
		MT) printf "Malta" ;;
		MX) printf "Mexico" ;;
		MY) printf "Malaysia" ;;
		NG) printf "Nigeria" ;;
		NL) printf "Netherlands" ;;
		NO) printf "Norway" ;;
		NP) printf "Nepal" ;;
		NZ) printf "New Zealand" ;;
		PA) printf "Panama" ;;
		PE) printf "Peru" ;;
		PH) printf "Philippines" ;;
		PL) printf "Poland" ;;
		PT) printf "Portugal" ;;
		QA) printf "Qatar" ;;
		RO) printf "Romania" ;;
		RS) printf "Serbia" ;;
		SA) printf "Saudi Arabia" ;;
		SE) printf "Sweden" ;;
		SG) printf "Singapore" ;;
		SI) printf "Slovenia" ;;
		SK) printf "Slovakia" ;;
		TR) printf "Turkey" ;;
		TW) printf "Taiwan" ;;
		UA) printf "Ukraine" ;;
		US) printf "United States" ;;
		UY) printf "Uruguay" ;;
		VE) printf "Venezuela" ;;
		VN) printf "Vietnam" ;;
		ZA) printf "South Africa" ;;
		*)  printf "%s" "$1" ;;
	esac
}

# provider_pia_get_server country_id country_name city_id city_name protocol vpn_type
# country_id: ISO code (e.g. "GB")   city_id: API region id (e.g. "uk")
# Returns the region's dns hostname (e.g. "uk-london.privacy.network").
provider_pia_get_server(){
	_ps_countryid="$1"
	_ps_cityid="$3"
	_psd="$SCRIPT_DIR/pia_serverdata"

	if [ ! -f "$_psd" ]; then
		Print_Output true "PIA: Server data missing — run refreshcacheddata" "$ERR"
		return 1
	fi

	if [ -n "$_ps_cityid" ] && [ "$_ps_cityid" != "0" ]; then
		jq -r --arg id "$_ps_cityid" \
			'.regions[] | select(.id == $id) | .dns' \
			"$_psd"
	else
		jq -r --arg c "$_ps_countryid" \
			'.regions[] | select(.country == $c and .offline == false) | .dns' \
			"$_psd" | head -1
	fi
}

# provider_pia_get_ovpn dns_hostname protocol vpn_type
# Constructs and prints a complete OVPN config.
# The CA cert is embedded; the CRL is read from the cached pia_crl.pem file.
provider_pia_get_ovpn(){
	_po_host="$1"
	_po_prot="$2"
	_po_type="$3"
	_po_crl="$SCRIPT_DIR/pia_crl.pem"

	case "$_po_prot" in
		TCP) _po_proto="tcp"; _po_port="502"  ;;
		*)   _po_proto="udp"; _po_port="1198" ;;
	esac

	case "$_po_type" in
		Strong) _po_cipher="aes-256-cbc"; _po_auth="sha256" ;;
		*)      _po_cipher="aes-128-cbc"; _po_auth="sha1"   ;;
	esac

	cat <<OVPN
client
dev tun
proto ${_po_proto}
remote ${_po_host} ${_po_port}
resolv-retry infinite
nobind
persist-tun
cipher ${_po_cipher}
auth ${_po_auth}
tls-client
remote-cert-tls server
auth-user-pass
compress
verb 1
reneg-sec 0
<ca>
-----BEGIN CERTIFICATE-----
MIIFqzCCBJOgAwIBAgIJAKZ7D5Yv87qDMA0GCSqGSIb3DQEBDQUAMIHoMQswCQYD
VQQGEwJVUzELMAkGA1UECBMCQ0ExEzARBgNVBAcTCkxvc0FuZ2VsZXMxIDAeBgNV
BAoTF1ByaXZhdGUgSW50ZXJuZXQgQWNjZXNzMSAwHgYDVQQLExdQcml2YXRlIElu
dGVybmV0IEFjY2VzczEgMB4GA1UEAxMXUHJpdmF0ZSBJbnRlcm5ldCBBY2Nlc3Mx
IDAeBgNVBCkTF1ByaXZhdGUgSW50ZXJuZXQgQWNjZXNzMS8wLQYJKoZIhvcNAQkB
FiBzZWN1cmVAcHJpdmF0ZWludGVybmV0YWNjZXNzLmNvbTAeFw0xNDA0MTcxNzM1
MThaFw0zNDA0MTIxNzM1MThaMIHoMQswCQYDVQQGEwJVUzELMAkGA1UECBMCQ0Ex
EzARBgNVBAcTCkxvc0FuZ2VsZXMxIDAeBgNVBAoTF1ByaXZhdGUgSW50ZXJuZXQg
QWNjZXNzMSAwHgYDVQQLExdQcml2YXRlIEludGVybmV0IEFjY2VzczEgMB4GA1UE
AxMXUHJpdmF0ZSBJbnRlcm5ldCBBY2Nlc3MxIDAeBgNVBCkTF1ByaXZhdGUgSW50
ZXJuZXQgQWNjZXNzMS8wLQYJKoZIhvcNAQkBFiBzZWN1cmVAcHJpdmF0ZWludGVy
bmV0YWNjZXNzLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAPXD
L1L9tX6DGf36liA7UBTy5I869z0UVo3lImfOs/GSiFKPtInlesP65577nd7UNzzX
lH/P/CnFPdBWlLp5ze3HRBCc/Avgr5CdMRkEsySL5GHBZsx6w2cayQ2EcRhVTwWp
cdldeNO+pPr9rIgPrtXqT4SWViTQRBeGM8CDxAyTopTsobjSiYZCF9Ta1gunl0G/
8Vfp+SXfYCC+ZzWvP+L1pFhPRqzQQ8k+wMZIovObK1s+nlwPaLyayzw9a8sUnvWB
/5rGPdIYnQWPgoNlLN9HpSmsAcw2z8DXI9pIxbr74cb3/HSfuYGOLkRqrOk6h4RC
OfuWoTrZup1uEOn+fw8CAwEAAaOCAVQwggFQMB0GA1UdDgQWBBQv63nQ/pJAt5tL
y8VJcbHe22ZOsjCCAR8GA1UdIwSCARYwggESgBQv63nQ/pJAt5tLy8VJcbHe22ZO
sqGB7qSB6zCB6DELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRMwEQYDVQQHEwpM
b3NBbmdlbGVzMSAwHgYDVQQKExdQcml2YXRlIEludGVybmV0IEFjY2VzczEgMB4G
A1UECxMXUHJpdmF0ZSBJbnRlcm5ldCBBY2Nlc3MxIDAeBgNVBAMTF1ByaXZhdGUg
SW50ZXJuZXQgQWNjZXNzMSAwHgYDVQQpExdQcml2YXRlIEludGVybmV0IEFjY2Vz
czEvMC0GCSqGSIb3DQEJARYgc2VjdXJlQHByaXZhdGVpbnRlcm5ldGFjY2Vzcy5j
b22CCQCmew+WL/O6gzAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEBDQUAA4IBAQAn
a5PgrtxfwTumD4+3/SYvwoD66cB8IcK//h1mCzAduU8KgUXocLx7QgJWo9lnZ8xU
ryXvWab2usg4fqk7FPi00bED4f4qVQFVfGfPZIH9QQ7/48bPM9RyfzImZWUCenK3
7pdw4Bvgoys2rHLHbGen7f28knT2j/cbMxd78tQc20TIObGjo8+ISTRclSTRBtyC
GohseKYpTS9himFERpUgNtefvYHbn70mIOzfOJFTVqfrptf9jXa9N8Mpy3ayfodz
1wiqdteqFXkTYoSDctgKMiZ6GdocK9nMroQipIQtpnwd4yBDWIyC6Bvlkrq5TQUt
YDQ8z9v+DMO6iwyIDRiU
-----END CERTIFICATE-----
</ca>
OVPN

	if [ -f "$_po_crl" ]; then
		printf '<crl-verify>\n'
		cat "$_po_crl"
		printf '</crl-verify>\n'
	fi

	printf 'disable-occ\n'
}

# provider_pia_get_comp
provider_pia_get_comp(){
	printf "adaptive"
}

# provider_pia_get_hmac
provider_pia_get_hmac(){
	printf "0"
}

# provider_pia_get_short_name server_id addr
# Returns the hostname prefix as a short label (e.g. "uk-london" from "uk-london.privacy.network").
provider_pia_get_short_name(){
	printf '%s' "$1" | cut -d'.' -f1
}

# provider_pia_write_certs vpn_no ovpn_detail
# Writes CA cert and CRL; removes unused cert files.
provider_pia_write_certs(){
	_wc_no="$1"
	_wc_ovpn="$2"

	_wc_ca="$(printf '%s' "$_wc_ovpn" | awk '/<ca>/{flag=1;next}/<\/ca>/{flag=0}flag' | sed '/^#/ d')"
	[ -z "$_wc_ca" ] && Print_Output true "PIA: Error extracting CA certificate" "$ERR" && return 1

	printf '%s\n' "$_wc_ca" > /jffs/openvpn/vpn_crt_client"${_wc_no}"_ca

	_wc_crl="$(printf '%s' "$_wc_ovpn" | awk '/<crl-verify>/{flag=1;next}/<\/crl-verify>/{flag=0}flag' | sed '/^#/ d')"
	if [ -n "$_wc_crl" ]; then
		printf '%s\n' "$_wc_crl" > /jffs/openvpn/vpn_crt_client"${_wc_no}"_crl
	else
		rm -f /jffs/openvpn/vpn_crt_client"${_wc_no}"_crl
	fi

	rm -f /jffs/openvpn/vpn_crt_client"${_wc_no}"_static
	rm -f /jffs/openvpn/vpn_crt_client"${_wc_no}"_key
	rm -f /jffs/openvpn/vpn_crt_client"${_wc_no}"_crt
}

# provider_pia_get_country_names
# Returns a sorted, deduplicated list of country display names.
provider_pia_get_country_names(){
	_psd="$SCRIPT_DIR/pia_serverdata"
	if [ ! -f "$_psd" ]; then
		Print_Output true "PIA: Server data missing — run refreshcacheddata" "$ERR"
		return 1
	fi
	jq -r '[.regions[] | select(.offline == false) | .country] | unique | .[]' "$_psd" \
		| while IFS= read -r _code; do
			_pia_country_name "$_code"
			printf '\n'
		done | sort -u
}

# provider_pia_get_country_id country_name
# Returns the ISO code for the given display name (e.g. "United Kingdom" → "GB").
provider_pia_get_country_id(){
	for _code in AD AE AL AM AR AT AU BA BD BE BG BO BR BS CA CH CL CN CO CR CY CZ DE \
	             DK DZ EC EE EG ES FI FR GB GE GL GR GT HK HR HU ID IE IL IM IN IS IT \
	             JP KH KR KZ LI LK LT LU LV MA MC MD ME MK MN MO MT MX MY NG NL NO NP \
	             NZ PA PE PH PL PT QA RO RS SA SE SG SI SK TR TW UA US UY VE VN ZA; do
		if [ "$(_pia_country_name "$_code")" = "$1" ]; then
			printf '%s' "$_code"
			return 0
		fi
	done
}

# provider_pia_get_city_count country_name
provider_pia_get_city_count(){
	_psd="$SCRIPT_DIR/pia_serverdata"
	_cid="$(provider_pia_get_country_id "$1")"
	jq -r --arg c "$_cid" \
		'[.regions[] | select(.country == $c and .offline == false)] | length' \
		"$_psd"
}

# provider_pia_get_city_names country_name
# Returns PIA region names for the given country (e.g. "UK London", "UK Manchester").
provider_pia_get_city_names(){
	_psd="$SCRIPT_DIR/pia_serverdata"
	_cid="$(provider_pia_get_country_id "$1")"
	jq -r --arg c "$_cid" \
		'.regions[] | select(.country == $c and .offline == false) | .name' \
		"$_psd" | sort
}

# provider_pia_get_city_id country_name city_name
# Returns the API region id (e.g. "uk") for the given region name.
provider_pia_get_city_id(){
	_psd="$SCRIPT_DIR/pia_serverdata"
	_cid="$(provider_pia_get_country_id "$1")"
	jq -r --arg c "$_cid" --arg n "$2" \
		'.regions[] | select(.country == $c and .name == $n) | .id' \
		"$_psd"
}

# provider_pia_country_required
# Returns 0 — country selection is required.
provider_pia_country_required(){
	return 0
}

# provider_pia_city_required
# Returns 0 — region/city selection is required to identify a specific endpoint.
provider_pia_city_required(){
	return 0
}

# provider_pia_get_types
provider_pia_get_types(){
	printf "Standard\nStrong\n"
}

# provider_pia_get_server_load desc
# Not available via PIA API.
provider_pia_get_server_load(){
	printf ""
}

# provider_pia_refresh_cache
# Downloads the PIA server list and the CRL.
# The server list API appends a detached signature after a blank line — strip it.
provider_pia_refresh_cache(){
	Print_Output true "PIA: Refreshing server data..."
	_psd="$SCRIPT_DIR/pia_serverdata"
	_pcrl="$SCRIPT_DIR/pia_crl.pem"
	_tmp_data="/tmp/pia_serverdata_$$"
	_tmp_crl="/tmp/pia_crl_$$.pem"

	/usr/sbin/curl -fsL --retry 3 \
		"https://serverlist.piaservers.net/vpninfo/servers/v6" \
		| awk '/^$/{exit}1' > "$_tmp_data"

	if ! jq -e '.regions | length > 0' "$_tmp_data" >/dev/null 2>&1; then
		Print_Output true "PIA: Failed to fetch server list — check connectivity" "$ERR"
		rm -f "$_tmp_data"
		return 1
	fi

	/usr/sbin/curl -fsL --retry 3 \
		"https://www.privateinternetaccess.com/openvpn/crl.rsa.2048.pem" \
		-o "$_tmp_crl"

	if [ -f "$_tmp_crl" ] && grep -q "BEGIN X509 CRL" "$_tmp_crl"; then
		mv "$_tmp_crl" "$_pcrl"
	else
		Print_Output true "PIA: CRL download failed — continuing without CRL" "$WARN"
		rm -f "$_tmp_crl"
	fi

	mv "$_tmp_data" "$_psd"
	_online=$(jq '[.regions[] | select(.offline == false)] | length' "$_psd")
	_total=$(jq '.regions | length' "$_psd")
	Print_Output true "PIA: Updated — ${_online} of ${_total} regions online" "$PASS"
}
