# vpnmgr

![CI](https://github.com/h0me5k1n/vpnmgr/actions/workflows/ci.yml/badge.svg)

VPN client manager for AsusWRT-Merlin routers. Manages up to five OpenVPN clients — server selection, scheduled refresh, OVPN config application, and a router WebUI tab.

## Supported firmware

Asuswrt-Merlin 384.15 / 384.13_4 or Fork 43E5 or later — [asuswrt-merlin.ng](https://asuswrt.lostrealm.ca/)

## Installation

From an SSH session on the router:

```sh
/usr/sbin/curl --retry 3 "https://raw.githubusercontent.com/h0me5k1n/vpnmgr/main/vpnmgr.sh" -o "/jffs/scripts/vpnmgr" && chmod 0755 /jffs/scripts/vpnmgr && /jffs/scripts/vpnmgr install
```

## Usage

vpnmgr adds a tab to the VPN section in the router WebUI.

To launch the interactive CLI menu over SSH:

```sh
vpnmgr
```

If that doesn't work (script not yet on `$PATH`):

```sh
/jffs/scripts/vpnmgr
```

## Provider status

| Provider | Status |
|----------|--------|
| **NordVPN** | Active — maintained and tested |
| **Private Internet Access (PIA)** | Untested — rewritten to use PIA JSON API; needs verification on a live account |
| **WeVPN** | Deprecated — WeVPN is no longer operational |

## Repository layout

```
vpnmgr/
├── vpnmgr.sh                   # Core script — CLI, scheduler, VPN client control, self-update
├── vpnmgr_www.asp              # WebUI page (AsusWRT-Merlin Addons API)
├── vpnmgr_www.js               # WebUI logic
├── vpnmgr_www.css              # WebUI styles
├── www/                        # Bundled web assets (served from /ext/vpnmgr/www/)
│   ├── jquery.js               # jQuery v3.5.1
│   └── detect.js               # LAN detection helper
├── providers/                  # Provider sub-scripts
│   ├── provider_nordvpn.sh     # NordVPN — active
│   ├── provider_pia.sh         # PIA — untested
│   ├── provider_surfshark.sh   # Surfshark — API tested
│   ├── provider_wevpn.sh       # WeVPN — deprecated
│   └── provider_template.sh   # Template for new providers
├── scripts/
│   ├── smoke-test.sh           # Local CI smoke test
│   ├── provider-test.sh        # Live API test harness for provider modules
│   ├── api-check.sh            # Scheduled API contract check (busybox ash)
│   ├── api-check-report.sh     # Opens/closes issues from API check results
│   └── api-checks/             # Per-provider assertions for api-check.sh
└── .github/workflows/
    ├── ci.yml                  # Runs smoke-test on every PR
    └── api-check.yml           # Daily provider API check
```

## Development

### Installing from a branch

Replace `<branch>` with the branch name:

```sh
/usr/sbin/curl --retry 3 "https://raw.githubusercontent.com/h0me5k1n/vpnmgr/<branch>/vpnmgr.sh" -o "/jffs/scripts/vpnmgr" && chmod 0755 /jffs/scripts/vpnmgr && /jffs/scripts/vpnmgr install
```

To switch a running installation between the stable release and the `develop` (pre-release) branch:

```sh
vpnmgr stable    # reinstalls from main
vpnmgr develop   # reinstalls from develop
```

Each command is a one-off reinstall from that branch. The installed script still checks `main` for updates, so run `vpnmgr develop` again to pick up later changes on `develop`.

### Testing a provider locally

Before deploying to a router, verify a provider's API integration works from your local machine (requires `curl` and `jq`):

```sh
bash scripts/provider-test.sh nordvpn
```

This exercises the live NordVPN API — country/city lookups, server recommendations, OVPN config download, and cert extraction — without touching any router state. `write_certs` is validated as a dry run: the CA and tls-auth blocks are extracted from the downloaded OVPN and verified, but nothing is written to the filesystem.

Providers marked `DEPRECATED` in their `# Status:` header skip network tests automatically.

### Automated API checks

Provider APIs change without notice, so a scheduled workflow (`.github/workflows/api-check.yml`) checks them every day. It runs each provider file, unmodified, under busybox ash in an Alpine container — the same shell the router uses — and verifies that every endpoint still responds and still returns the fields the provider reads. Once a week, and on pull requests that touch a provider, it also builds an OpenVPN client config from the provider's output and attempts a login with fake credentials: being rejected at the login step proves the server address, port, protocol, CA certificate and TLS auth key are all correct.

When a check fails for an `ACTIVE` or `API_TESTED` provider, an issue labelled `api-check` is opened with the output, and closed automatically when the check passes again.

To run it yourself (requires Docker):

```sh
docker run --rm -v "$PWD:/repo:ro" alpine:3.24 sh -c \
  'apk add -q --no-cache curl jq openssl openvpn && sh /repo/scripts/api-check.sh nordvpn --handshake'
```

It exits `0` when everything passes, `1` when an endpoint is gone or its response has changed, and `2` when the result is inconclusive (rate limited, blocked, or no response).

### Provider status

Each provider file declares its status on line 3:

| Status | Meaning |
|--------|---------|
| `ACTIVE` | Connected end-to-end on a real router with a live account. Installed by default and shown in the WebUI. |
| `API_TESTED` | Passes the automated API check including the OpenVPN handshake, but nobody has yet connected with a real account. Not installed by default. |
| `UNTESTED` | Written but not verified. |
| `UNMAINTAINED` | Used to work; no longer maintained. |
| `DEPRECATED` | The provider's service is offline. |

If you have an account with an `API_TESTED` provider and can confirm it connects, that is what it needs to become `ACTIVE` — see the manual testing steps in `CLAUDE.md`.

### Adding a provider

Copy `providers/provider_template.sh` to `providers/provider_<name>.sh` and implement all 17 required functions. The contract is documented in the template header.

Then copy `scripts/api-checks/template.sh` to `scripts/api-checks/<name>.sh` and list the response fields your provider reads. The automated API check picks the new provider up from its file name; no workflow change is needed.

Run `bash scripts/smoke-test.sh` locally before opening a PR — CI enforces this on every push.

### Shell compatibility

All `.sh` files must be **busybox ash compatible**. No bash arrays, no `[[ ]]`, no `let`, no `declare`, no process substitution. The router does not have bash.

## VPN keepalive & logging

As of `v3.1.0`, vpnmgr no longer overrides the OpenVPN `ping`/`ping-restart`
keepalive directives for any provider. Earlier versions hardcoded `ping 15`
/ `ping-restart 60` and explicitly discarded whatever the VPN server itself
pushed (`pull-filter ignore "ping"` / `pull-filter ignore "ping-restart"`).
Since pushing tuned keepalive values via `PUSH_REPLY` is standard practice
for commercial VPN providers (NordVPN's own published Asuswrt-Merlin setup
guide, for example, sets only `ping-timer-rem` and relies on its servers'
pushed values), the old override could turn brief, harmless network jitter
into a full reconnect far more often than necessary — for some users this
showed up as frequent `Inactivity timeout (--ping-restart), restarting`
lines flooding the syslog. `ping-timer-rem` is still set, so the
ping-restart countdown still resets on any received packet.

**If you're upgrading from an earlier version**: this is a behaviour change
for every managed VPN client — the actual keepalive timeout now comes from
your provider instead of a fixed 60 seconds. If your provider (or its
specific server) pushes an unusually short or missing keepalive and you see
different reconnect behaviour after upgrading, please open an issue.

Two new per-client settings (menu option `8`, or WebUI equivalent) control
log volume and detail instead:

| Setting | Default | Effect |
|---|---|---|
| `mute` | `20` | Emits OpenVPN's `mute <N>` directive, collapsing N consecutive identical log lines into a single summary line. Set to `0` to disable. |
| `debugverb` | `false` | When enabled, adds `verb 4` for detailed OpenVPN diagnostic logging. Leave off unless actively debugging a connection issue, since it increases log volume. |

## Known limitations

- **NordVPN OVPN format**: vpnmgr downloads OVPN files from NordVPN's CDN, which still serves the v1 format (tls-auth, multiple `remote` lines). NordVPN's newer v2.6 format (tls-crypt, single `remote`) is only available via manual download from the NordVPN portal — no programmatic per-server URL is known. The v1 CDN files work correctly; upgrading to v2.6 would require NordVPN to expose an API endpoint for per-server downloads.

- **Migrating from jackyaz's version**: if you currently have [jackyaz/vpnmgr](https://github.com/jackyaz/vpnmgr) installed, you must uninstall it first before installing this version. Run `vpnmgr uninstall` using the old script, then follow the installation instructions above. The install command will detect an existing installation and refuse to proceed if one is found.

## Roadmap

- [x] **Phase 1** — Fork merge: jackyaz's v2.3.2 merged as the new baseline; WeVPN ZIP files removed
- [x] **Phase 2** — Modular providers: all provider logic extracted to `providers/`; CI smoke test added
- [x] **Phase 3** — Branding sweep: URLs, integrity check, and banner updated to h0me5k1n
- [x] **Phase 4** — Web assets: `jquery.js` and `detect.js` bundled in `www/`; `jackyaz/shared-jy` dependency removed
- [x] **Phase 5** — WebUI modernisation: dynamic provider loading from `providers.htm`; ES5-clean JS; inline script blob replaced with external `vpnmgr_www.js`
- [ ] **Phase 6** — Documentation: provider authoring guide, contributing guide, CLI/WebUI screenshots
- [ ] **Phase 7** — Migration: automated detection of jackyaz's install with guided uninstall prompt

## Project history

1. **[h0me5k1n/vpnmgr](https://github.com/h0me5k1n/vpnmgr)** — the original project, NordVPN-only CLI.

2. **[jackyaz/vpnmgr](https://github.com/jackyaz/vpnmgr)** — [@jackyaz](https://github.com/jackyaz) forked and massively expanded it across 429 commits: full WebUI, multi-provider support, scheduled refresh, self-update. Now archived. His work is the backbone of this codebase and is preserved in full in the commit history.

3. **This repo** — jackyaz's fork merged back as the new baseline, revived and maintained by h0me5k1n.

## Credits

- [@jackyaz](https://github.com/jackyaz) — author of the expanded vpnmgr. His 429 commits are the foundation of this codebase.
- [@h0me5k1n](https://github.com/h0me5k1n) — original concept and current maintainer.

## Licence

GPL-3.0 — see [LICENSE](LICENSE).

## Supporting development

Love the script and want to support future development? Any and all donations gratefully received!

| [![paypal](https://www.paypalobjects.com/en_GB/i/btn/btn_donate_LG.gif)](https://www.paypal.com/donate/?hosted_button_id=6FWFBJL3A3FL6) <br /><br /> [**PayPal donation**](https://www.paypal.com/donate/?hosted_button_id=6FWFBJL3A3FL6) | [![QR code](https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=https://www.paypal.com/donate/?hosted_button_id=6FWFBJL3A3FL6)](https://www.paypal.com/donate/?hosted_button_id=6FWFBJL3A3FL6) |
| :----: | --- |

## Help and issues

Open an issue on this repo, or post in the [Asuswrt-Merlin AddOns forum on SNBForums](https://www.snbforums.com/forums/asuswrt-merlin-addons.60/?prefix_id=11).
