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
| **NordVPN** | Untested — the profile changes below await live account and router validation |
| **Private Internet Access (PIA)** | API tested — needs verification on a live account |
| **Surfshark** | API tested — needs verification on a live account |
| **WeVPN** | Deprecated — WeVPN is no longer operational |

The provider file's `# Status:` header is authoritative. The WebUI normally lists only `ACTIVE` providers; automated checks and local fixtures do not establish live support.

## OpenVPN profiles and custom settings

VPNMgr detects the router's built-in `/usr/sbin/openvpn` version. NordVPN uses legacy download URLs below OpenVPN 2.6 and the modern `_2.6` URLs on 2.6 and later. If detection fails, VPNMgr reports the unknown version and uses the legacy fallback. The WebUI displays this backend result; Save always uses a fresh backend detection.

Custom settings use separate shared, UDP and TCP lists for each family, with the selected client's provider, protocol, mute and debug settings. Legacy NordVPN keeps its MTU settings and UDP `mssfix`; modern profiles use OpenVPN's defaults for those options. `persist-key` is omitted on 2.7 and later. UDP-only options are excluded from TCP. `fast-io` is omitted because VPNMgr cannot establish that the router has no effective traffic shaping.

CLI Choice 7 accepts individual clients, ranges and comma-separated combinations, such as `1,3-5`. Disabling VPNMgr custom settings leaves the existing custom-options block in place. The existing removal of a stale `verify-x509-name` restriction during server changes still applies. There is no custom-options backup, restore or migration feature.

WebUI Save reserves an apply request before submitting settings and shows separate results for all five clients. Saved settings, configuration apply and connection results are reported separately. A failed or unconfirmed apply preserves the form; **Continue checking** follows the same request, and **Reload saved settings** explicitly reloads the page. Save stays disabled until complete settings and a valid runtime response have loaded.

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
│   ├── provider_nordvpn.sh     # NordVPN — untested profile rework
│   ├── provider_pia.sh         # PIA — API tested
│   ├── provider_surfshark.sh   # Surfshark — API tested
│   ├── provider_wevpn.sh       # WeVPN — deprecated
│   └── provider_template.sh   # Template for new providers
├── scripts/
│   ├── smoke-test.sh           # Local CI smoke test
│   ├── provider-test.sh        # Live API test harness for provider modules
│   ├── api-check.sh            # Scheduled API contract check (busybox ash)
│   ├── api-check-report.sh     # Opens/closes issues from API check results
│   ├── changelog-notes.sh      # Extracts a version's CHANGELOG.md section
│   └── api-checks/             # Per-provider assertions for api-check.sh
├── CHANGELOG.md                # What changed in each release
└── .github/workflows/
    ├── ci.yml                  # Runs smoke-test on every PR
    ├── api-check.yml           # Daily provider API check
    └── release.yml             # Tags and publishes each release from main
```

## Development

### Installing from a branch

Resolve a branch once and pass that exact revision to the installer, so the initial script and its assets share the same source. For the upstream development branch:

```sh
repository=h0me5k1n/vpnmgr
branch=develop
sha="$(/usr/sbin/curl -fsL --retry 3 -H 'Accept: application/vnd.github.sha' \
  "https://api.github.com/repos/$repository/commits/$branch")" || exit 1
case "$sha" in ''|*[!0-9a-fA-F]*) exit 1 ;; esac
[ "${#sha}" -eq 40 ] || exit 1
/usr/sbin/curl -fsL --retry 3 \
  "https://raw.githubusercontent.com/$repository/$sha/vpnmgr.sh" \
  -o /jffs/scripts/vpnmgr && chmod 0755 /jffs/scripts/vpnmgr && \
  VPNMGR_INSTALL_SHA="$sha" VPNMGR_INSTALL_BRANCH="$branch" /jffs/scripts/vpnmgr install
```

To switch a running installation between the stable release and the `develop` (pre-release) branch:

```sh
vpnmgr stable    # reinstalls from main
vpnmgr develop   # reinstalls from develop
```

Each command is a one-off reinstall from that branch. The installed script still checks `main` for updates, so run `vpnmgr develop` again to pick up later changes on `develop`.

After `vpnmgr develop`, the CLI header and the WebUI version show which commit is installed, e.g. `v3.4.1 (develop@9a18d5f)`. Every file in that install comes from that one commit. Installing from `main` again, with `vpnmgr stable` or a normal update, removes the label.

Installed full-revision metadata also controls asset repair, including builds with the same version number. Updates resolve a fresh candidate. Explicitly pinned development builds stop before downloads if their revision cannot be established; ordinary unpinned installs retain the historical branch fallback and report `unknown` provenance when the lookup fails.

For controlled NordVPN testing while its status is `UNTESTED` or `API_TESTED`, set `VPNMGR_TEST_PROVIDERS=nordvpn` when invoking `install` or `forceupdate`. This persists a WebUI visibility opt-in for NordVPN without changing its status. Invoke an update with `VPNMGR_TEST_PROVIDERS=` to remove the opt-in. Other inactive providers are not enabled by it. Live account, generated router configuration, negotiated cipher, traffic and reconnect checks remain necessary.

### Testing a provider locally

Before deploying to a router, verify a provider's API integration works from your local machine (requires `curl` and `jq`):

```sh
bash scripts/provider-test.sh nordvpn
bash scripts/provider-test.sh nordvpn modern
```

These exercise the live NordVPN API — country/city lookups, server recommendations, OVPN config download, and cert extraction — without touching router state. The first command selects legacy profiles; the second selects modern profiles. Certificate handling is a dry run, including the profile's `tls-auth` or `tls-crypt` block.

Providers marked `DEPRECATED` in their `# Status:` header skip network tests automatically.

### Automated API checks

Provider APIs change without notice, so a scheduled workflow (`.github/workflows/api-check.yml`) checks them every day under BusyBox ash in an Alpine container. NordVPN checks cover both profile families and both transports by default (`--profile-family=legacy|modern|both` can select a family). Weekly and relevant PR checks also attempt a login with fake credentials. Reaching `AUTH_FAILED` checks the path through the control-channel exchange to login rejection; it does not verify a real login, negotiated data cipher, traffic or reconnect.

When a check fails for an `ACTIVE` or `API_TESTED` provider, an issue labelled `api-check` is opened with the output, and closed automatically when the check passes again.

Offline checks include `bash scripts/smoke-test.sh --offline` and `node scripts/webui-contract-test.js`. With an existing compatible Chrome and ChromeDriver, `node scripts/webui-browser-test.js` runs one isolated browser against loopback firmware fixtures. It uses the real ASP, JavaScript and jQuery, with no router access or package installation. Set `CHROME_BINARY` or `CHROMEDRIVER` if needed. Browser fixtures and CI are separate from live router acceptance.

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
