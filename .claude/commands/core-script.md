# Skill: Core Script Development (vpnmgr.sh)

## Purpose

This skill covers development of `vpnmgr.sh` — the core orchestrator script that runs on the AsusWRT-Merlin router. Read `CLAUDE.md` first for project-wide context.

## Script Anatomy

vpnmgr.sh is a single monolithic ash script that serves as:
1. **CLI menu interface** — interactive terminal menu for manual management
2. **Scheduler** — cron job management via `cru` for automated server refresh
3. **VPN client controller** — reads/writes NVRAM values to configure OpenVPN clients
4. **Provider dispatcher** — sources and calls provider sub-scripts
5. **Self-updater** — checks GitHub for new versions and applies updates
6. **WebUI backend** — generates data files read by the ASP/JS frontend

## Shell Compatibility Rules (CRITICAL)

This script runs under **busybox ash** on an Asus router. Violations will cause silent failures or syntax errors on the router.

### NEVER use:
```sh
# Bash arrays
declare -a arr=()          # FAILS
local -a arr               # FAILS
arr=(one two three)        # FAILS — unless using set -- positional params

# Double brackets
[[ "$var" == "value" ]]    # FAILS — use [ "$var" = "value" ]

# Process substitution
while read line < <(cmd)   # FAILS — use cmd | while read line

# Here strings
grep "x" <<< "$var"        # FAILS — use printf '%s' "$var" | grep "x"

# Bash-specific parameter expansion
${var,,}                   # FAILS — use printf '%s' "$var" | tr 'A-Z' 'a-z'
${var^^}                   # FAILS
${var:offset:length}       # OK in some busybox builds but avoid

# Associative arrays
declare -A map             # FAILS completely

# 'function' keyword
function myFunc() {}       # FAILS — use myFunc() {}

# let, (( )), arithmetic beyond $(( ))
let x=1                    # Unreliable
(( x++ ))                  # FAILS — use x=$((x + 1))

# [[ with regex
[[ "$var" =~ pattern ]]    # FAILS — use expr or grep
```

### SAFE patterns:
```sh
# Conditionals
[ "$var" = "value" ]
[ -f "/path/to/file" ]
[ "$num" -gt 5 ]

# Loops
for item in one two three; do ...; done
while read -r line; do ...; done

# Subshells and command substitution
result=$(command)
result=$(command | grep pattern)

# Arithmetic
x=$((x + 1))
[ "$x" -gt "$y" ]

# Local variables — busybox ash supports `local`, but provider modules avoid it in
# favour of _prefixed globals to prevent scoping surprises across sourced functions.
# In the core script, `local` is fine where scope is well-contained.
local var="value"   # OK in core script functions

# Positional parameter tricks (poor man's arrays)
set -- "item1" "item2" "item3"
for item do echo "$item"; done

# String operations via external tools
echo "$var" | tr 'A-Z' 'a-z'
echo "$var" | sed 's/old/new/g'
echo "$var" | cut -d'=' -f2
echo "$var" | awk -F',' '{print $1}'
```

## Key Functions Reference

### Output & Logging
```sh
Print_Output <toLog> <message> <severity>
# toLog: true/false — whether to also write to syslog
# severity: $PASS (green), $WARN (yellow), $ERR (red), $CRIT (red bold)
# Example: Print_Output true "VPN client 1 updated successfully" "$PASS"
```

### NVRAM Interaction (VPN Client Configuration)
The script reads and writes VPN client config via `nvram`:
```sh
nvram get vpn_client${VPN_NO}_addr        # Server address
nvram get vpn_client${VPN_NO}_port        # Port
nvram get vpn_client${VPN_NO}_proto       # Protocol (tcp-client / udp)
nvram get vpn_client${VPN_NO}_desc        # Description shown in WebUI
nvram get vpn_client${VPN_NO}_username     # Auth username
nvram get vpn_client${VPN_NO}_password     # Auth password
nvram set vpn_client${VPN_NO}_addr="$SERVER"
nvram commit                               # Persist changes
```

VPN client numbers are 1-5 on current Merlin firmware.

### Scheduling (cru)
```sh
# Add a cron job
cru a vpnmgr_${VPN_NO} "30 */4 * * * /jffs/scripts/vpnmgr refreshcacheddata ${VPN_NO}"

# Delete a cron job
cru d vpnmgr_${VPN_NO}

# List cron jobs
cru l | grep vpnmgr
```

### Settings File
Location: `/jffs/addons/vpnmgr.d/vpnmgr.conf` (or `/jffs/configs/vpnmgr.conf` on older installs)

Format is simple key=value:
```
vpn1_managed=true
vpn1_provider=nordvpn
vpn1_protocol=udp
vpn1_type=standard
vpn1_countryid=228
vpn1_countryname=United Kingdom
vpn1_cityid=0
vpn1_cityname=
vpn1_schenabled=true
vpn1_schhours=*/4
vpn1_schmins=30
vpn1_customsettings=true
vpn2_managed=false
...
```

Reading: `grep "vpn${VPN_NO}_provider" "$SCRIPT_CONF" | cut -f2 -d"="`
Writing: `sed -i "s/^vpn${VPN_NO}_provider.*$/vpn${VPN_NO}_provider=${PROVIDER}/" "$SCRIPT_CONF"`

### Provider Dispatch Pattern

After modularisation, the core script dispatches to providers like this:

```sh
PROVIDERS_DIR="/jffs/addons/vpnmgr.d/providers"

Load_Provider() {
    local provider="$1"
    local provider_script="${PROVIDERS_DIR}/provider_${provider}.sh"
    if [ -f "$provider_script" ]; then
        . "$provider_script"
    else
        Print_Output true "Provider module not found: $provider" "$ERR"
        Print_Output true "Run 'vpnmgr update' to download provider modules" "$WARN"
        return 1
    fi
}

# Usage in the refresh flow:
Refresh_VPN_Client() {
    local vpn_no="$1"
    local provider
    provider=$(grep "vpn${vpn_no}_provider" "$SCRIPT_CONF" | cut -f2 -d"=")

    Load_Provider "$provider" || return 1

    local country city protocol vpn_type
    country=$(grep "vpn${vpn_no}_countryid" "$SCRIPT_CONF" | cut -f2 -d"=")
    city=$(grep "vpn${vpn_no}_cityid" "$SCRIPT_CONF" | cut -f2 -d"=")
    protocol=$(grep "vpn${vpn_no}_protocol" "$SCRIPT_CONF" | cut -f2 -d"=")
    vpn_type=$(grep "vpn${vpn_no}_type" "$SCRIPT_CONF" | cut -f2 -d"=")

    local server
    server=$("provider_${provider}_get_server" "$country" "$city" "$protocol" "$vpn_type")

    if [ -z "$server" ]; then
        Print_Output true "No server returned for VPN client $vpn_no" "$ERR"
        return 1
    fi

    # Download OVPN to temp, extract settings, apply via nvram
    local ovpn_file="/tmp/vpnmgr_${vpn_no}.ovpn"
    "provider_${provider}_get_ovpn" "$server" "$protocol" > "$ovpn_file"

    Apply_OVPN_To_Client "$vpn_no" "$ovpn_file" "$server"
    rm -f "$ovpn_file"
}
```

### Self-Update Flow

Use the existing source-selection functions rather than constructing a second
download URL. `Pin_Script_Repo` resolves the selected repository/branch to one
revision. `Bootstrap_Install` verifies/refetches the main script at that revision
before installation; providers and WebUI/supporting files use the same source.

`Update_Check` downloads a validated candidate once, compares version/content,
and also detects changed source identity. `.install_revision` identifies the
installed script source; `.files_source` is recorded only after asset refresh
succeeds. A failed refresh must remain retryable. Preserve source metadata when
re-executing an update and retain the normal branch-switching commands.

## Version Bumping (REQUIRED)

`SCRIPT_VERSION` is defined at the top of `vpnmgr.sh` (`readonly SCRIPT_VERSION="vX.Y.Z"`).

**These files count as router-delivered changes for release versioning:**
- `vpnmgr.sh` itself
- Any `providers/provider_*.sh` file
- `vpnmgr_www.asp`, `vpnmgr_www.js`, or anything under `www/`

Pinned-source installs and updates can refresh changed assets even when
`SCRIPT_VERSION` is unchanged. That mechanism does not replace release versioning.

The bump happens once per release, on `develop`, before the PR from `develop` into `main`, together with renaming `## Unreleased` in `CHANGELOG.md` to the new version (see `CLAUDE.md`, Branch workflow). CI enforces it there: the `version-bump` job in `.github/workflows/ci.yml` will fail a PR into `main` if router-delivered files changed but the version didn't. Follow semver:

| Change type | Bump |
|-------------|------|
| Breaking change or major refactor | Major (`v3.0.0 → v4.0.0`) |
| New provider, new feature | Minor (`v3.0.0 → v3.1.0`) |
| Bug fix, small tweak | Patch (`v3.0.0 → v3.0.1`) |

## Common Tasks

### Adding a new CLI menu option
1. Add the option letter/number to the `ScriptHeader` / menu display function
2. Add the case branch in the main menu `while` loop
3. Follow the pattern: validate input → execute → print result

### Adding a new setting
1. Add the key to `Generate_Config` (default value)
2. Add the setting read in the relevant function
3. Add the setting write in the relevant update function
4. If visible in WebUI — also update `vpnmgr_www.asp` and `vpnmgr_www.js`

### Testing changes

Use the committed checks appropriate to the changed behavior:

```sh
# CI smoke test — validates all provider contracts, sourcing, and function presence.
# Must stay green before every commit. CI enforces this on every PR.
bash scripts/smoke-test.sh

# Live provider API test — exercises a provider against its real API without a router.
# Requires curl and jq. Run before opening a PR for any provider change.
bash scripts/provider-test.sh nordvpn
bash scripts/provider-test.sh pia
```

Offline fixtures cover runtime detection, presets/Choice 7, profile validation,
backend requests, pinned-source installation/downloads and banner rendering:
`scripts/openvpn-runtime-test.sh`, `openvpn-presets-test.sh`,
`api-profile-test.sh`, `webui-backend-test.sh`, `source-download-test.sh`,
`install-source-test.sh` and `banner-test.sh`. Run them with `sh`; CI also runs
them under BusyBox ash. The banner's `--busybox` mode requires BusyBox. On macOS,
the install-source fixture requires GNU-compatible `sed` on its process `PATH`.

Check shell syntax/lint and use the committed JavaScript/browser checks described
in [webui.md](webui.md) for UI changes. These fixtures do not prove native router
configuration, real-account authentication or tunnel traffic. Live installation,
settings changes, file copies and restarts require the operator's explicit scope;
record the installed/served revision separately from local or simulated results.
