# WebUI development

Read `CLAUDE.md` first. The product uses ES5 JavaScript and jQuery; Node test
runners may use the host's current JavaScript syntax.

## Files and serving

- `vpnmgr_www.asp` contains the page, inline styles, firmware forms and ASP data
  injection. `Mount_WebUI` copies it to a registered `userN.asp` under `/www/user`.
- `vpnmgr_www.js` contains the client logic. The saved copy is under
  `/jffs/addons/vpnmgr.d`; `Create_Symlinks` copies it into the served directory.
- Bundled jQuery and `detect.js` are loaded from `/ext/vpnmgr/www/`. Keep global
  `$` available for firmware code; use `var $j = jQuery` for this page.
- The current page uses inline styles, not the standalone `vpnmgr_www.css` file.
- Load `/js/httpApi.js` before `/client_function.js`. Preserve the existing
  firmware includes and `document.form` / `document.formScriptActions` names.

Keep the existing fixed-width table layout and dark theme. Use `var`, ordinary
functions and `$j.ajax`; no frameworks, template literals, arrow functions or
browser `fetch` in product code. Update the saved and served files together.

## Reads

| Endpoint | Content |
| --- | --- |
| `/ext/vpnmgr/config.htm` | Per-client `key=value` settings |
| `/ext/vpnmgr/providers.htm` | Available provider `id\|displayname` lines |
| `/ext/vpnmgr/nordvpn_countrydata.htm` | Cached NordVPN country/city JSON |
| `/ext/vpnmgr/<provider>_countrydata.htm` | Other providers' cached country text |
| `/ext/vpnmgr/runtime/detection_<id>.json` | Request-specific backend runtime |
| `/ext/vpnmgr/runtime/apply_<id>.json` | Reservation/apply status |
| `/ext/vpnmgr/vpnmgrserverloads.js` | Existing server-load utility data |

The WebUI never calls provider APIs directly. Preserve text after the first `=`
when parsing settings. Require complete client settings before enabling Save.
Unavailable saved providers and locations must remain visible rather than being
silently replaced. Rebuilding settings must replace previous client tables.

## Runtime detection

`DetectRuntime` POSTs `start_vpnmgrruntime_<id>` to `/start_apply.htm` with the
control form. Then it polls the matching JSON file until a bounded timeout.
The result contains `request`, `state`, `version`, `number`, `family`, `status`.
Only matching, valid `done` results enable Save. An unknown runtime is an explicit
backend result with empty version/number and the documented legacy fallback.
Missing or malformed results keep Save disabled and expose retry.

Display the backend family read-only. Do not add a family selector, compare
versions in JavaScript or send a browser-selected family to the backend.
`UpdateVPNConfig` detects again when applying, so stale browser data cannot choose
a different profile or preset family after a router update.

## Save and result correlation

1. Validate and capture a fresh scalar settings payload from all five sections,
   preserving unrelated addon/version keys and credentials. Capture the current
   protocol/provider/custom flags, disabled fields and schedule selections.
2. POST `start_vpnmgrprepare_<id>` using only the control form. Do not send
   `amng_custom` until its matching status says `ready`. A `busy` response must
   leave the form available without submitting settings.
3. POST the captured main-form fields with `start_vpnmgrapply_<id>` and JSON
   `amng_custom`, including the matching `vpnmgr_request_id`.
4. Poll only `apply_<id>.json`. Check request/state/client schema, display all
   five results, and distinguish `merged`, apply status and connection status.
5. Freeze configuration inputs during an outstanding apply, preserving their
   prior disabled states. Restore them at terminal results; retain edits.
   A timeout remains unconfirmed. Continue checking the SAME request without
   resubmitting; reload saved settings only on an explicit user action.

Use AJAX `dataType:'text'` for control/apply POST responses. Merlin's
`start_apply.htm` returns executable callback/reload JavaScript; it must remain
inert. Do not submit Save through the hidden iframe, override global firmware
callbacks or use a fixed timer to announce success/reload the page.

## Backend privacy and lifecycle

`Runtime_Prepare` serializes cooperating VPNMgr requests before their payload
POST. `Runtime_Apply` checks the reservation and nonce, snapshots shared settings
privately, merges, and reports each client's actual outcome. It cleans up owned
snapshots and locks on ordinary completion/interruption. This is not a global
transaction against independent/legacy writers of Merlin's shared settings file.

Public JSON is in `/tmp/vpnmgr-runtime`, linked as `/ext/vpnmgr/runtime/`. Private
snapshots use its separate sibling directory `/tmp/vpnmgr-runtime-private` with
mode 0700; never put credentials or raw errors into served JSON. Preserve finite
status/message codes, atomic JSON writes and propagation of publication failures.

## Validation

- `node --check vpnmgr_www.js`
- `node scripts/webui-contract-test.js` for quick request/payload/state contracts.
- `sh scripts/webui-backend-test.sh` for actual isolated backend functions;
  CI also runs this under BusyBox ash.
- `node scripts/webui-browser-test.js` for one existing Chrome/ChromeDriver
  session against loopback firmware fixtures, the real ASP/JS and bundled jQuery.
  Optional paths: `CHROME_BINARY`, `CHROMEDRIVER`. No package installation or
  router access. Fixtures cover runtime families/unknown, all five sections,
  repeated Save/reload, protocol/provider/custom/schedule edits and error recovery.

Fixtures and CI do not establish live router support. Actual served-file hashes,
Merlin-generated configuration, real authentication, negotiated cipher, traffic
and reconnect need separately authorized live validation.
