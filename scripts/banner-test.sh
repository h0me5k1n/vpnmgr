#!/bin/sh
# Render the production banner without running the manager or touching a router.
set -eu
ROOT="$(CDPATH='' cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
case "${1:-}" in
	--busybox)
		command -v busybox >/dev/null
		mkdir "$TEST_DIR/bin"
		printf '#!/bin/sh\nexec busybox awk "$@"\n' > "$TEST_DIR/bin/awk"
		chmod 0755 "$TEST_DIR/bin/awk"
		PATH="$TEST_DIR/bin:$PATH"; export PATH
	;;
	'') ;;
	*) printf 'Usage: %s [--busybox]\n' "$0" >&2; exit 1 ;;
esac
sed -n '/^ScriptHeader(){/,/^}/p' "$ROOT/vpnmgr.sh" > "$TEST_DIR/header"
# shellcheck source=/dev/null
. "$TEST_DIR/header"
clear(){ :; }
# Formatting variables are consumed by the extracted production function.
export BOLD='' CLEARFORMAT=''
SCRIPT_VERSION=v3.4.1
SCRIPT_SOURCE_FILE="$TEST_DIR/source"
check_banner(){
	_label="$1"; ROUTER_MODEL="$2"; _grow="$3"
	if [ -n "$_label" ]; then printf '%s\n' "$_label" > "$SCRIPT_SOURCE_FILE"; else rm -f "$SCRIPT_SOURCE_FILE"; fi
	ScriptHeader > "$TEST_DIR/output" 2> "$TEST_DIR/error"
	if [ -s "$TEST_DIR/error" ]; then cat "$TEST_DIR/error" >&2; exit 1; fi
	# Assert complete equal-width borders, not just the rows printed before an
	# awk failure. This catches the router's unsupported dynamic printf format.
	awk '
		NF {
			if (!width) { width = length($0); if ($0 !~ /^#+$/) exit 1 }
			if (length($0) != width || $0 !~ /^##.*##$/) exit 1
			last = $0; rows++
		}
		END { if (rows < 12 || last !~ /^#+$/) exit 1 }
	' "$TEST_DIR/output"
	grep -Fq "$SCRIPT_VERSION on $ROUTER_MODEL" "$TEST_DIR/output"
	if [ -n "$_label" ]; then
		grep -Fq "from $_label" "$TEST_DIR/output"
	else
		if grep -q 'from ' "$TEST_DIR/output"; then exit 1; fi
	fi
	_width="$(awk 'NF { print length($0); exit }' "$TEST_DIR/output")"
	if [ "$_grow" = yes ]; then [ "$_width" -gt 55 ]; else [ "$_width" -eq 55 ]; fi
}
check_banner '' GT-AX11000 no
check_banner develop@0123456 GT-AX11000 no
check_banner feat/openvpn-profile-custom-settings@0123456 GT-AX11000 no
check_banner feature/a-very-long-branch-name-that-needs-a-wider-banner-than-the-original-box@0123456 GT-AX11000 yes
check_banner '' A-very-long-router-model-name-that-needs-a-wider-banner-than-the-original-box yes
printf 'CLI banner rendering and dynamic width checks passed (%s).\n' "${1:-local awk}"
