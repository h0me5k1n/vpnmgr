# vpnmgr — Claude Code Project Guide

## What this is

**vpnmgr** is a VPN client management tool for AsusWRT-Merlin routers. It manages up to five
OpenVPN clients — server selection, OVPN config application, scheduled refresh, and a router WebUI tab.

Originally created by h0me5k1n as `nvpnmgr` (NordVPN-only CLI), massively expanded by jackyaz
(WebUI, multi-provider, self-update, scheduled refresh — 429 commits, now archived). The current
repo merges jackyaz's work as the baseline and restructures it into a modular provider architecture.

## Current state

| Phase | Status | Notes |
|-------|--------|-------|
| 1 — Fork merge | ✅ Done | jackyaz/vpnmgr v2.3.2 merged; WeVPN ZIPs removed |
| 2 — Modular providers | ✅ Done | `providers/` sub-scripts; zero inline provider logic in core |
| 3 — URL/branding sweep | ✅ Done | `SCRIPT_REPO`, integrity check, banner updated to h0me5k1n |
| 4 — WebUI | ⏸ Deferred | shared-jy dependency removed; full modernisation pending |
| 5 — Documentation | ✅ Done | README rewritten |

CI: `bash scripts/smoke-test.sh` — runs on every PR to `main` and `develop`.
Local provider test: `bash scripts/provider-test.sh <provider>` — live API without a router.
API check: `scripts/api-check.sh` — runs daily in CI (`.github/workflows/api-check.yml`) and on
PRs that touch a provider. Unmodified provider files, busybox ash, live API. See below.

## Provider status

Check the `# Status:` header (line 3) of each file in `providers/` — that is always the source
of truth. Do not rely on any listing in docs.

| Status | Meaning |
|--------|---------|
| `ACTIVE` | Connected end-to-end on a real router with a live account |
| `API_TESTED` | `api-check.sh --handshake` passes in CI; never connected with a live account |
| `UNTESTED` | Written, nothing verified |
| `UNMAINTAINED` / `DEPRECATED` / `TEMPLATE` | See the provider-module skill |

`API_TESTED` exists for providers nobody on the project has an account for. On the router it
behaves exactly like `UNTESTED`: not installed, hidden from the WebUI, usable from the CLI if the
file is fetched by hand. `API_TESTED` and `ACTIVE` both require `scripts/api-checks/<name>.sh`
(the smoke test enforces this), and a PR touching a provider at either status fails if its API
check does not pass.

**Rule: any change to a provider resets its `# Status:` to `API_TESTED` if the API check passes
on the PR, otherwise to `UNTESTED`. It returns to `ACTIVE` only once the change is verified
end-to-end with a live account on a real router.**

**Install convention:** `Install_Providers` in `vpnmgr.sh` lists only `ACTIVE` providers. When
promoting a provider to `ACTIVE`, add it to that loop in the same PR.

## API check

`scripts/api-check.sh <provider> [--handshake]` must run as root in a container, because it
installs a logging shim at `/usr/sbin/curl` and writes to `/jffs/openvpn`:

```sh
docker run --rm -v "$PWD:/repo:ro" alpine:3.24 sh -c \
  'apk add -q --no-cache curl jq openssl openvpn && sh /repo/scripts/api-check.sh nordvpn --handshake'
```

- A generic baseline runs for every provider using only the function contract, then
  `api_check_<name>` from `scripts/api-checks/<name>.sh` adds provider-specific assertions.
- `--handshake` builds an OpenVPN config from the values `UpdateVPNConfig` would store and the
  files `write_certs` wrote, then expects `AUTH_FAILED` with fake credentials. This sends a
  deliberate failed login to the provider, so it runs weekly and on PRs, not daily.
- Exit codes: `0` pass, `1` contract broken, `2` inconclusive (403/429/5xx/no response), `3`
  usage or environment error. NordVPN answers 403 rather than 404 for unknown paths, so a 403
  from a host that answered other requests in the same run counts as `1`.
- `scripts/api-check-report.sh` opens, comments on and closes issues labelled `api-check` for
  `ACTIVE` and `API_TESTED` providers. It never edits a status header; demotion is a manual PR.
- Scheduled workflows only run from the default branch, and GitHub disables them after 60 days
  without repository activity.

## Technical constraints

### Shell compatibility — CRITICAL
All `.sh` files run under **busybox ash** on the router. Violations cause silent failures.

Never use:
- `[[ ]]` — use `[ ]`
- bash arrays — use newline-delimited strings + `while IFS= read -r`
- `let x=1` — use `x=$((x + 1))`
- `declare` / `typeset`
- `${var,,}` / `${var^^}` — use `tr`
- Process substitution `<(cmd)` — use temp files in `/tmp/`
- `function` keyword — use `name() {}`

Use `_prefixed` variables inside provider functions (not `local`) — providers are sourced and
`local` can cause unexpected scoping when functions call each other.

### Dependencies
- `jq` — hard requirement for all JSON parsing. Must be installed on dev machine and router
  (Entware: `opkg install jq`).
- `/usr/sbin/curl` — always call curl via this path in provider scripts (the router binary).
  The local test harness patches it to `curl --globoff` automatically.

### Never commit
- `*.ovpn`, `*.zip`, `*.pem`, `*.p12` — provider configs/certs are downloaded at runtime

### Other constraints
- Run `bash scripts/smoke-test.sh` before every commit — every test must pass
- Feature branches only — `main` is protected

### Branch workflow
Routers install and update straight from `main`, so merging to `main` is the release.

- Branch from `develop` and open PRs into `develop`. No `SCRIPT_VERSION` bump is needed there.
- Test on a router with `vpnmgr develop`, which reinstalls everything from `develop`.
- To release, bump `SCRIPT_VERSION` on `develop` and open one PR from `develop` into `main`.
  CI enforces the bump on that PR.
- If a fix has to go directly to `main`, merge `main` back into `develop` afterwards.
- No Co-Authored-By trailers in commits
- Commit style: `type: description` (feat, fix, refactor, docs, chore)

## Repository layout

```
vpnmgr/
├── vpnmgr.sh                    # Core — CLI, scheduler, VPN client control, self-update
├── vpnmgr_www.asp               # WebUI page (AsusWRT-Merlin Addons API)
├── vpnmgr_www.js                # WebUI logic
├── vpnmgr_www.css               # WebUI styles
├── www/                         # Bundled web assets
├── providers/
│   ├── provider_nordvpn.sh      # ACTIVE
│   ├── provider_pia.sh          # UNTESTED
│   ├── provider_surfshark.sh    # API_TESTED
│   ├── provider_wevpn.sh        # DEPRECATED
│   └── provider_template.sh     # Template for new providers
├── scripts/
│   ├── smoke-test.sh            # CI smoke tests
│   ├── provider-test.sh         # Live API test harness
│   ├── api-check.sh             # Scheduled API contract check (busybox ash, container only)
│   ├── api-check-report.sh      # Issue open/close logic for the API check workflow
│   └── api-checks/              # Per-provider assertions + template.sh
├── .claude/
│   └── commands/                # Skill files (used by Claude Code)
├── .github/workflows/
│   ├── ci.yml                   # Smoke test + version bump check
│   └── api-check.yml            # Daily API check, weekly handshake
├── CLAUDE.md                    # This file
└── README.md
```

## Available skills

| Command | File | Use for |
|---------|------|---------|
| `/provider-module` | `.claude/commands/provider-module.md` | Adding or editing a provider |
| `/core-script` | `.claude/commands/core-script.md` | Working on `vpnmgr.sh` |
| `/bootstrap` | `.claude/commands/bootstrap.md` | Project phase reference |
| `/webui` | `.claude/commands/webui.md` | Working on the WebUI |

Always read the relevant skill before starting work on that area.

## Manual provider testing on a real router

To test an `API_TESTED` or `UNTESTED` provider that isn't yet in the `Install_Providers` loop:

1. SSH to the router
2. Fetch the provider file directly (replace `main` with your branch if testing pre-merge):
   ```sh
   /usr/sbin/curl -fsL --retry 3 \
     "https://raw.githubusercontent.com/h0me5k1n/asusmerlin-nvpnmgr/main/providers/provider_<name>.sh" \
     -o "/jffs/addons/vpnmgr.d/providers/provider_<name>.sh"
   chmod 0755 "/jffs/addons/vpnmgr.d/providers/provider_<name>.sh"
   ```
3. Run `vpnmgr` — the provider will appear in the slot configuration menu
4. Test end-to-end: country/city selection, `get_server` returns a hostname, OVPN applies to
   the client slot, VPN tunnel connects, server load shows in WebUI
5. If passing: set `# Status: ACTIVE` in the provider file, add
   the provider name to the `Install_Providers` loop in `vpnmgr.sh`, run both test scripts,
   open a PR

Check router tunnel state: `ifconfig tun1x` / `nvram get vpn_client1_state`
Check router logs: `logread` or `/tmp/syslog.log`

## Key output conventions

```sh
# Messages go through Print_Output (writes to syslog + terminal):
Print_Output true "message" "$PASS"   # green
Print_Output true "message" "$WARN"   # yellow
Print_Output true "message" "$ERR"    # red

# Data (server hostnames, country lists, OVPN content) goes to stdout.
# These must not be mixed — any debug output during a data function goes to stderr via Print_Output.
```
