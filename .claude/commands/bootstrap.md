# Bootstrap: Fork Merge & Restructure

This is the historical fork-revival plan. Its phase commands are not the current
development or installation procedure. See [CLAUDE.md](../../CLAUDE.md),
[core-script.md](core-script.md) and [webui.md](webui.md) for current source,
update and validation behavior.

## Context

You are helping revive the `vpnmgr` project. The upstream fork by jackyaz (https://github.com/jackyaz/vpnmgr, now archived) is the true baseline — it has 429 commits of improvements over the original h0me5k1n/asusmerlin-nvpnmgr repo.

Read `CLAUDE.md` first for full project context.

## Phase 1: Repository Setup

### 1.1 — Merge jackyaz's fork as the new baseline

```bash
# Assuming we're in the cloned h0me5k1n/asusmerlin-nvpnmgr repo
git remote add jackyaz https://github.com/jackyaz/vpnmgr.git
git fetch jackyaz
git checkout -b pre-merge-backup main    # safety branch
git checkout main
git reset --hard jackyaz/master
git push origin main --force
```

> After this, rename the repo to `vpnmgr` via GitHub Settings → General → Repository name.
> GitHub will auto-redirect the old URL.

### 1.2 — Remove provider-specific committed files

Delete these files (provider configs must never live in the repo):
- `wevpn_tcp_standard.zip`
- `wevpn_udp_standard.zip`

Commit: `chore: remove committed provider config files — configs are downloaded at runtime`

## Phase 2: Modularise Provider Logic

### 2.1 — Create the provider directory and contract

Create `providers/` directory. Create `providers/provider_template.sh` as the reference implementation contract (see `provider-module.prompt.md` for the full specification).

### 2.2 — Extract NordVPN logic from vpnmgr.sh

Audit `vpnmgr.sh` and identify all NordVPN-specific functions. These typically include:
- Server recommendation via NordVPN API (`https://api.nordvpn.com/v1/servers/recommendations`)
- OVPN config download from NordVPN CDN
- NordVPN country/city list retrieval
- NordVPN-specific credential handling
- Server load checking (`getServerLoad` function)

Extract these into `providers/provider_nordvpn.sh`, implementing the provider contract functions.

### 2.3 — Extract PIA logic (preserve but mark unsupported)

The original PIA implementation downloaded a ZIP of OVPN files (requiring 7za / Entware).
PIA now exposes a JSON API at `serverlist.piaservers.net/vpninfo/servers/v6` covering 91 countries
with no ZIP dependency. The provider has been fully rewritten to use this API.

```sh
# Provider: Private Internet Access (PIA)
# Status: UNTESTED — rewritten using PIA JSON API; needs verification on a live account
```

See `.prompts/provider-module.prompt.md` for the full provider contract and the UNTESTED rule.

### 2.4 — Extract WeVPN logic (preserve but mark deprecated)

Extract WeVPN-specific functions into `providers/provider_wevpn.sh`. Add a header comment:
```sh
# Provider: WeVPN
# Status: DEPRECATED — WeVPN is no longer operational
# Retained for reference only. Do not use.
```

### 2.5 — Refactor vpnmgr.sh core to use provider dispatch

Replace inline provider logic with a dispatch pattern:

```sh
# Source the appropriate provider module
Load_Provider() {
    local provider="$1"
    local provider_script="/jffs/addons/vpnmgr.d/providers/provider_${provider}.sh"
    if [ -f "$provider_script" ]; then
        . "$provider_script"
        return 0
    else
        Print_Output true "Provider module not found: $provider" "$ERR"
        return 1
    fi
}

# Dispatch to provider function
Provider_Get_Server() {
    local provider="$1"
    shift
    Load_Provider "$provider" || return 1
    "provider_${provider}_get_server" "$@"
}
```

The core script should have ZERO provider-specific API URLs, country lists, or config formats — all of that lives in the provider modules.

## Phase 3: Update Self-Referencing URLs and Branding

### 3.1 — Update script repo URL

Find and replace all instances of:
- `https://raw.githubusercontent.com/jackyaz/vpnmgr/master` → `https://raw.githubusercontent.com/h0me5k1n/vpnmgr/master`
- `github.com/jackyaz/vpnmgr` → `github.com/h0me5k1n/vpnmgr`

### 3.2 — Update integrity check

The self-update function greps for `jackyaz` to verify the downloaded script is genuine. Change to `h0me5k1n`:
```sh
# Old
/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | grep -qF "jackyaz" || { ... }
# New
/usr/sbin/curl -fsL --retry 3 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | grep -qF "h0me5k1n" || { ... }
```

### 3.3 — Update banner/header

Update the ASCII banner in the script to show:
```
#  vpnmgr — VPN Client Manager for AsusWRT-Merlin
#  https://github.com/h0me5k1n/vpnmgr
#  Originally by h0me5k1n, expanded by jackyaz
#  Revived and maintained by h0me5k1n
```

### 3.4 — Update donation links

Remove or replace jackyaz's PayPal/BuyMeACoffee links in the README and any embedded in the WebUI.

## Phase 4: Update Installation Path

### 4.1 — Provider module installation

The install function needs to also deploy provider modules:
```sh
Install_Providers() {
    mkdir -p "/jffs/addons/vpnmgr.d/providers"
    for provider in nordvpn; do
        /usr/sbin/curl -fsL --retry 3 \
            "$SCRIPT_REPO/providers/provider_${provider}.sh" \
            -o "/jffs/addons/vpnmgr.d/providers/provider_${provider}.sh"
        chmod 0755 "/jffs/addons/vpnmgr.d/providers/provider_${provider}.sh"
    done
}
```

### 4.2 — Provider module self-update

Each provider module should have its own `PROVIDER_VERSION` variable. The core update check should also check and update provider modules.

## Phase 5: README and Documentation

Write a new README.md covering:
- Project history and credits (h0me5k1n origin → jackyaz expansion → h0me5k1n revival)
- Current scope: NordVPN actively maintained, PIA unmaintained, WeVPN deprecated
- Installation instructions (updated curl one-liner)
- Usage (CLI menu + WebUI)
- Provider module architecture (how to add a new provider)
- Contributing guidelines
- Licence (GPL-3.0)

## Verification Checklist

After completing all phases:
- [ ] `bash scripts/smoke-test.sh` passes (all tests green)
- [ ] `bash scripts/provider-test.sh nordvpn` passes (live API — requires curl + jq)
- [ ] `shellcheck vpnmgr.sh` passes (with existing directives)
- [ ] `shellcheck providers/provider_nordvpn.sh` passes
- [ ] `shellcheck providers/provider_pia.sh` passes
- [ ] No `jackyaz` references remain in functional code (only in credits/history)
- [ ] No OVPN/ZIP/credential files in the repo
- [ ] All curl URLs point to `h0me5k1n/vpnmgr`
- [ ] Provider dispatch works — core script has no inline provider logic
- [ ] WebUI still loads and renders correctly with provider changes
- [ ] Self-update mechanism points to correct repo
- [ ] README accurately reflects the project state
