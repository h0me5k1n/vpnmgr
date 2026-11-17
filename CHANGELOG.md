# Changelog

Changes that reach routers, and changes to how providers are maintained. Each release is published as a [GitHub release](https://github.com/h0me5k1n/vpnmgr/releases) from its section below.

Versions before v3.4.0 have no entries here; see the [commit history](https://github.com/h0me5k1n/vpnmgr/commits/main).

<!--
Contributors: record changes in the same PR as the change, under a
"## Unreleased" heading at the top of the list (add the heading if it isn't
there). At release it is renamed to the version and date. Never leave an
empty "## Unreleased" heading; the smoke test rejects one.
-->

## Unreleased

### Added

- Automatically select NordVPN legacy or modern profiles from the router's built-in OpenVPN version. Report unknown versions explicitly and use the legacy fallback.
- Separate legacy/modern shared, UDP and TCP custom-settings lists using each client's current provider, transport and logging settings. Choice 7 accepts individual slots, ranges and mixed comma-separated selections.
- Show backend runtime detection in WebUI Utilities and detailed apply/connection outcomes in the browser console. Reserve each Save before submitting its payload, retain edits on failures and allow continued checking of an unconfirmed request.

### Fixed

- Keep the WebUI runtime readout read-only, with automatic checks on page load and console-only manual diagnostics. Allow the backend a polling interval before the first runtime/apply result read, report missing results and still-ready reservations as informational pending notices, and log the final detection outcome.
- Use Merlin's standard applying-settings overlay and reload after confirmed success, with clear failures and console diagnostics instead of a permanent Apply status panel. Preserve edits and firmware status polling when completion fails or remains unconfirmed.
- Restore the managed VPN client list and current custom-setting states before Choice 7's batch-selection prompt.
- Size the CLI banner to fit the version, router model and development source label, using padding compatible with the router's BusyBox awk and keeping its borders aligned for long branch names.
- Recover a lost WebUI settings POST by expiring only its unused reservation, preserving edits and late/running request correlation without resubmitting settings. Report clients restored to stopped accurately and retain unavailable location IDs only for unchanged selections.
- Make normal direct installs verify/refetch their own pinned main script before installing dependencies, with automatic NordVPN visibility in pinned test builds. Preserve ordinary `unknown` branch-fallback reentry and the existing `develop`/`stable` switching paths.
- Preflight NordVPN CA and control-channel key material before updating active client state. Handle legacy `tls-auth` and modern `tls-crypt`, normalize CRLF profiles and preserve existing certificate verification.
- Refresh scripts, providers and WebUI assets from one selected revision, including same-version builds. Preserve revision metadata across update re-execution and distinguish completed asset refreshes from installed source provenance.
- Reject incomplete WebUI settings, preserve unavailable configured providers and rebuild a fresh scalar payload for each Save.

### Repository

- Add offline runtime, preset, profile, backend and source/download fixtures, BusyBox CI execution, WebUI contracts and isolated real-browser journeys. NordVPN remains `UNTESTED` pending the required PR/live validation; a separate explicit development flag permits controlled WebUI testing.

## v3.4.1 (2026-10-25)

### Fixed

- **Merlin WebUI initialization:** load `httpApi.js` before `client_function.js` to fix the partially rendered VPN Manager page and `httpApi is not defined` errors. Remove the obsolete `tmhist.js` and `tmmenu.js` includes that return 404 on newer firmware. (#62)
- **Merlin 3006 VPN setup:** check the firmware family before comparing legacy build numbers, so `3006.102.9` is not treated as older than the `384.x`/`386.x` releases. Set Connection Retry attempts to `0` instead of invalid `-1` and avoid obsolete routing defaults. Preserve the existing version boundaries for older firmware. (#62)
- **Managed OpenVPN custom options:** regenerate VPNMgr's managed options in the active per-client `custom3` file on Merlin 3006 when custom settings are enabled. This prevents stale imported server-name restrictions from blocking server changes while retaining CA validation and `remote-cert-tls server`. With VPNMgr custom settings disabled, the user's own custom options are not replaced (see #63 for the one exception). (#62)
- **CLI WebUI URL:** read Merlin's active menu tree to resolve the registered page number, preventing false `WebUI page not found` messages or outdated links when the temporary menu copy differs from the active menu. (#62)
- **Server switching with custom settings disabled:** remove a `verify-x509-name` line from the user's custom options when VPNMgr updates the client. An imported profile's line pins the previous server's certificate name, so the new server failed the TLS handshake. Everything else in the block is left as it was, and CA validation still applies. (#63)
- **Uninstall now removes per-client scheduled updates.** The `vpnmgr_VPN1`–`vpnmgr_VPN5` cron jobs and the `services-start` lines that recreate them at boot were left behind, pointing at the deleted script. (#64)
- **WebUI console warning:** remove the page's `onunload` handler. It called the firmware's empty `unload_body()`, so it did nothing, and current Chrome blocks `unload` handlers with a "Permissions policy violation" warning. The firmware's own `unload` and Permissions-Policy warnings remain. (#66)

The #62 fixes were verified on ASUS RT-BE88U with Merlin `3006.102.9` and GT-AX11000 with Merlin `388.12_2`.

### Repository

- Add offline regression tests for firmware-family routing, retry and custom-options behavior, including imported server-name restrictions and disabled custom settings, plus active-menu CLI URL discovery. (#62)

## v3.4.0 (2026-10-18)

### Added

- **Searchable country and city picker** in slot setup. Type part of a name to filter, use Tab or the arrow keys to move, Enter to pick and Esc to cancel. Matching ignores case, spaces and punctuation. Terminals without raw key input get a numbered list that can be narrowed by typing. (#49)
- **Installed commit shown for `develop` installs.** After `vpnmgr develop`, the CLI header and the WebUI version show which commit is installed, for example `v3.4.0 (develop@9a18d5f)`, and every file in the install comes from that one commit. Installs from `main` (`vpnmgr stable` or a normal update) show only the version. (#53)
- **`API_TESTED` provider status**, for providers that pass the automated API check, including an OpenVPN handshake, but have not been connected with a live account. On the router it behaves like `UNTESTED`: not installed by default and not shown in the WebUI. Surfshark and PIA move to this status. (#48)

### Fixed

- **PIA:** all 112 countries in PIA's server list can be selected. 21 of them were listed as bare country codes with no cities. (#50, #52)
- **PIA:** tls-auth is disabled, since PIA's configs have no tls-auth key. (#51, #52)

### Repository

- A scheduled workflow checks every provider against its live API daily, with a weekly OpenVPN handshake check, and opens an `api-check` issue when an `ACTIVE` or `API_TESTED` provider breaks. (#48)
- Each release is tagged and published as a GitHub release from this changelog.
