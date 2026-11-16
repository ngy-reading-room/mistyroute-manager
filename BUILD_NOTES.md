# MistyRoute Manager — BUILD_NOTES.md

## v0.1.0 — read-only demo (2026-11-16)

**What it is:** a Flutter management app for a 3x-ui (Xray) VPN panel.
Read-only in v0.1 — no write actions yet.

- Project: `~/workspace/mistyroute-manager/`
- Package: `com.ngy.mistyroutemanager` (Dart package `mistyroutemanager`)
- Version: `0.1.0+1` (shown in the app bar as `v0.1.0`)
- Flutter 3.47.9 / Dart 3.13.7 (same toolchain as NGY Reading Room)
- Title: "MistyRoute Manager"

**Repo:** https://github.com/ngy-reading-room/mistyroute-manager (public, org `ngy-reading-room`)
- `main` branch: app source (commit `900fd72`)
- `gh-pages` branch: built site only (commit `35aa965`)

**Live demo:** https://ngy-reading-room.github.io/mistyroute-manager/
- GitHub Pages, source `gh-pages` branch, root. No Netlify credits used.
- Verified 2026-11-16: Pages status `built`; index HTTP 200;
  `main.dart.js` served md5 `56ba2b4b79b3a6b645c8dcbb85b75578` — identical
  to the local build; `<base href="/mistyroute-manager/">`; title correct.

## What v0.1 does

- **Dashboard / Bandwidth monitor**
  - Inbound totals card: per-inbound up/down/total GB.
  - Live server-status card: Xray state + version, CPU %, memory,
    uptime, net up/down speed (from `server/status`).
  - Flags row (tap to filter): ≥80% quota, expiring ≤7 days, disabled.
  - Client list sorted by usage desc. Each row: name (the panel's
    `email`/remark field), ↑/↓/used GB, quota GB, used-% bar,
    expiry date + days-left, enabled/disabled state.
- **User detail:** tap a client → full details (remark, inbound, status,
  up/down/used/quota, % bar, expiry, days left).
- **Settings:** Panel URL + API token fields (persisted on-device only —
  SharedPreferences, i.e. browser local storage on web), "Use demo data"
  toggle (default ON), Save, Test connection, Clear saved credentials.
- **Data source:** `PanelApiService`
  - `GET {base}panel/api/inbounds/list`, header
    `Authorization: Bearer <token>`, envelope `{success, msg, obj}`.
    Shape verified against `vpn-api-collect.py` (the daily check's read
    path): inbound `{remark, up, down, clientStats[]}`,
    client `{email, up, down, total, expiryTime, enable}`.
    `total` = quota bytes (0 = unlimited); `expiryTime` = epoch ms
    (0 = no expiry). Model computes used GB, quota GB, used %,
    expiry date, days-to-expiry — same math as the Python collector.
  - `GET {base}panel/api/server/status`, same Bearer auth. Shape
    VERIFIED against the public MHSanaei/3x-ui source
    (`web/service/server.go` `Status` struct, via pkg.go.dev + deepwiki):
    `obj.netIO.up/down` = live bytes/sec, `obj.cpu`, `obj.mem.current/total`,
    `obj.xray.state/version`, `obj.uptime`. Parsing is tolerant (only
    the fields the dashboard shows are read); a failed call yields
    "Live status unavailable" instead of breaking the dashboard.
- **Demo data mode:** 24 fictional clients ("Demo User 01"–"Demo User 24"),
  same shapes as the real API: 3 over 80% quota, 3 expiring ≤7d,
  1 expired, 2 disabled, 2 unlimited. No real client names, quotas or
  traffic anywhere in the repo or the build (verified by grep:
  0 hits for the tunnel host, real client names, `gho_` tokens,
  `api_token` paths). The dashboard shows a `DEMO DATA` badge in this mode.

## Gates (2026-11-16)

- `flutter analyze`: **No issues found!**
- `flutter test`: **1 passed** (smoke test: boots to the dashboard with
  24 demo clients, flags counts 3/3/2).
- `flutter build web --release --base-href /mistyroute-manager/`: OK
  (`build/web` 41 MB, mostly CanvasKit 37 MB; `main.dart.js` 2.6 MB).

## Mock vs live

- MOCK (shown by default): all 24 clients, inbound totals, server status.
- LIVE (implemented, NOT yet tested against the real panel): the
  workspace cannot reach the panel (Cloudflare 403 on our egress IP),
  so the live path was never exercised end-to-end. It needs the user's
  browser tab (which can reach the panel) or the Android APK.
- KNOWN UNKNOWN — CORS on web: the panel does not advertise CORS
  headers, so a browser fetch from the Pages host may be blocked by
  the browser even when the panel is up and the token is right. The
  Android APK has no CORS restriction and is the reliable live route.
  The live error card surfaces the failure reason instead of guessing.

## Security

- The panel URL and API token are NEVER hardcoded — not in code, assets,
  README, or git history. They are entered only at runtime in Settings.
- The token is a bearer master key: it bypasses the panel's web login +
  2FA (same as the daily check). It is stored only on-device and sent
  only to the panel URL the user entered. If a device is lost, the token
  must be regenerated on the VPS (panel Settings → Security → API Token).

## Left for v0.2

- Write actions: add client, renew (extend expiry + reset traffic +
  remark dates per the panel conventions), extend quota (×1.35 rule),
  enable/disable, delete. (Panel's client endpoints — same API family
  as the read path; add/delete shapes to be verified against the live
  panel before wiring them.)
- Google Sheets sync (`vlesslist`): panel → sheet auto-write with ISO
  dates (panel stays truth); sheet → panel add later.
- Live-speed polish: confirm `server/status` against the real v3.11.0
  panel (fields already verified from source; needs one live response).
- Android APK build (`build-apk.sh`-style release flow) for the phone.
- Search/sort options on the client list.

## v0.2 spec (from user, 2026-11-16 19:39)

First-run setup screen with click buttons (no typing):
1. **SSH connect** — `ssh root@168.144.250.99` (app holds its own SSH keypair; public key installed on VPS).
2. **Check Tunnel link** — run on VPS: `grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /var/log/cloudflared-panel.log | tail -1`, then append `/MjfgiJflHcfijX4TYv/` to form the full panel URL.
3. **Tunnel Restart (optional)** — `ssh vps 'systemctl restart cloudflared-panel.service'`.

Design: VPS authorized_keys entry uses a forced-command dispatch script allowing ONLY `url` and `restart` (no arbitrary shell). Ordering: restart first, then check link — the hostname may change after a restart. Token still entered once in Settings (stable). Other v0.2 items: write actions (add/renew/quota x1.35/reset/enable/delete), Google Sheets sync (vlesslist, panel -> sheet, ISO dates), APK build, client search/sort. Sequence: v0.1 live test first (CORS unknown decides web-vs-APK for live data), then build v0.2 on the user's go-ahead.

- API-only login (user requirement, 2026-11-16 19:40): the app authenticates to the 3x-ui panel exclusively via the API Bearer token. No username/password/2FA fields anywhere in the app, ever. Token entered once in Settings, stored on-device.

- Tunnel status check (user request, 2026-11-16 19:49): `systemctl status cloudflared-panel.service`, `tail -5 /var/log/cloudflared-panel.log`, `systemctl is-active cloudflared-panel.service` (run on VPS as root). For v0.2: add a `status` action to the SSH dispatch script (url + restart + status) so the app gets a tunnel-status button.

## v0.2.0 — write actions + SSH setup + Sheets sync (2026-11-16)

**What it is:** same app, now with write actions, a first-run SSH Setup
tab, and a Google Sheets sync (panel -> `vlesslist`).

- Version: `0.2.0+2` (shown in the app bar as `v0.2.0`)
- APK: `MistyRoute_Manager-v0.2.0.apk` (58.4 MB, versionCode 2),
  AppDev Drive file id `1_yny8E4Co2cpH0t02MPu2_uxwpflRO7w`,
  md5 `a80abc38d76750421abf6a05b0f854b4` (Drive checksum matches local).
  Signed with the persistent debug keystore
  (`~/workspace/tools/android-debug.keystore`, SHA-1
  `2A:F2:AC:97:7F:A8:9D:3C:01:9F:A7:61:BB:63:B4:4D:55:CF:CC:C6` —
  verified with apksigner). Build: `~/workspace/tools/build-apk-mistyroute.sh release`
  (copy of build-apk.sh with ROOT + versioned filename changed).
  First attempt failed (Gradle daemon died after 489s — the VM was
  memory-starved: 1.1 GB available with the Gradle + Kotlin daemons
  holding ~2.3 GB); killed the stale daemons, retried, built in 235s.
  Lesson: if a release build dies with "daemon disappeared", check
  `free -m` first and kill stale Gradle/Kotlin daemons before retrying.
- Web demo: https://ngy-reading-room.github.io/mistyroute-manager/
  (rebuilt + redeployed, `main.dart.js` md5
  `72a51e27d2c2a63514bad8ddeb24f18d`).

### Write actions (all verified against the MHSanaei/3x-ui source, commit 85e2ded, module v3)

- Endpoints (`/panel/api/clients/...`, Bearer token, `{success, msg, obj}` envelope):
  `GET get/:email` -> `{client: <ClientRecord>, inboundIds: [...]}`
  `POST add` body `{"client": <model.Client>, "inboundIds": [id]}`
  `POST update/:email` body raw `<model.Client>`
  `POST del/:email?keepTraffic=1`
  `POST resetTraffic/:email`
- **UUID rule:** `Update` runs `fillProtocolDefaults`, which generates
  a NEW UUID when the body's `id` is empty. Every update therefore
  GETs the record first and sends the existing UUID as `id` — or the
  client's subscription link breaks.
- **Quota rule:** `model.Client.totalGB` is `int64` (whole GB) in the
  official v3 model (pkg.go.dev v3.7.0 + latest). Fractional GB (91.1)
  would fail Go's JSON unmarshal and reject the request. Quotas are
  always sent as whole GB; x1.35 rounds to the nearest whole GB
  (67.5 -> 91, 60 -> 81, 100 -> 135). The live panel's clientStats
  `total` can still show fractional GB — that byte value lives in the
  traffic table, not the record.
- **Renew** = new remark dates (start today, +N calendar months, day
  clamped) + panel expiry = end date + 1 day 00:00 + reset traffic.
  The remark IS the `email` field, so renewal renames via the update
  endpoint (the panel UI's own path).
- **Add:** UUID left empty (panel generates it), flow
  `xtls-rprx-vision`, subId = stable name, remark per convention.
- **Delete** asks for confirmation; `keepTraffic=0` (traffic + IP
  rows deleted too).
- In demo mode every action applies to the in-memory sample data and
  says "(simulated)".

### SSH Setup tab (mobile only)

- App generates its own Ed25519 keypair on first use (pinenacl
  `SigningKey.generate()` -> `OpenSSHEd25519KeyPair`; dartssh2 4.1.0
  has NO key generation — verified in the resolved package source).
  Private key PEM in secure storage (flutter_secure_storage 11.2.0);
  public line + SHA256 fingerprint shown for install.
- One-tap buttons send ONLY `url` / `restart` / `status` as the remote
  command (plus a connect test that only authenticates). The VPS
  forced-command script `scripts/mistyroute-ctl` allows exactly those
  three words — no shell. Order: restart first, then Check Tunnel Link
  (hostname changes on restart); the link button offers "Save this as
  the panel URL".
- Host keys: trust-on-first-use, fingerprint stored in secure storage,
  mismatch aborts.
- Web shows "not available on web, use the APK" (browsers have no TCP).
- VPS install (user does this): copy `scripts/mistyroute-ctl` to
  `/root/mistyroute-ctl` (mode 700), append the authorized_keys line
  from the app's Setup tab (with the `command="..."` prefix + the
  no-* restrictions) to `/root/.ssh/authorized_keys`.
- minSdk raised to 23 (flutter_secure_storage v11 needs Android 6.0+).
  Release signing uses the persistent debug keystore (same as Reading
  Room) so the SHA-1 stays stable.

### Google Sheets sync (panel -> `vlesslist`)

- Implemented: row builder (header + Name/Inbound/Status/Used GB/
  Quota GB/Used %/Expiry/Days left; expiry ISO `yyyy-MM-dd` only) +
  Sheets API v4 `values.update` REST call (PUT, `USER_ENTERED`).
  Unit-tested with a fake HTTP client.
- **NOT yet usable — needs the user (Cloud Console, one time):**
  1. Enable the Google Sheets API in the project that owns the sheet.
  2. Create an Android OAuth client ID: package
     `com.ngy.mistyroutemanager`, SHA-1
     `2A:F2:AC:97:7F:A8:9D:3C:01:9F:A7:61:BB:63:B4:4D:55:CF:CC:C6`.
  3. Put that client's `google-services.json` in `android/app/` and
     rebuild the APK.
  4. Make sure the signed-in Google account can edit the spreadsheet.
  5. In the app: Settings -> Google Sheets -> paste the spreadsheet
     ID (or full URL) -> Sign in with Google -> Sync now.
  Until then the app shows these exact steps (it cannot do them
  itself). Sign-in uses google_sign_in 7.2.0 (`GoogleSignIn.instance`,
  `initialize()` once, `authenticate()`, `authorizationClient.
  authorizeScopes([sheets scope])`).

### Gates (2026-11-16)

- `flutter analyze`: **No issues found!**
- `flutter test`: **26 passed** (was 1): renewal/quota/remark math,
  write-request paths + bodies (fake HTTP), Sheets rows + REST write,
  SSH command building + keypair PEM round-trip, widget smoke test.
  The widget test mocks the secure-storage method channel (no plugin
  in the test env) so the Setup tab's key load completes.
- `flutter build web --release --base-href /mistyroute-manager/`: OK
  (`main.dart.js` md5 `72a51e27d2c2a63514bad8ddeb24f18d`).
- APK verified: aapt package `com.ngy.mistyroutemanager`
  versionCode 2 / versionName 0.2.0; apksigner verify OK.

### Security (unchanged + new)

- Panel URL, API token, SSH private key: runtime-only (Settings /
  secure storage), never in code, assets, README, or git history.
  Grep-verified: 0 hits for the tunnel host, real client names,
  `gho_` tokens, `api_token` paths in the repo or the built JS.
  The only `trycloudflare.com` strings are the grep pattern in
  `mistyroute-ctl` and the URL matcher in the SSH service — no real
  hostname. The VPS IP (168.144.250.99) and panel sub-path
  (`/MjfgiJflHcfijX4TYv/`) are in the code because SSH and the
  dispatch script need them; the tunnel hostname itself is never
  stored (it randomizes on restart).

### Left for the user (live verification, phone)

- Install v0.2.0 APK from AppDev; paste panel URL + API token in
  Settings; turn demo data OFF; confirm the live list loads.
- Try one write action on a test client first (renew or quota x1.35),
  then check the panel web UI shows the change.
- Setup tab: install `mistyroute-ctl` + the authorized_keys line on
  the VPS (see above), then SSH Connect -> Check Tunnel Link.
- Sheets: do the 5 Cloud Console steps above, then Sync now.
- Web demo render check in a real browser (the v0.1 7/7 check was a
  cloud-browser pass; this build was verified by analyze + tests +
  md5 only).

---

## v0.2.1+3 (2026-11-16) — fixes + icon + group filter + Fix names + Billing

NayGyi confirmed the v0.2.0 live test (LIVE, 24 clients) and asked for
the real editable app + a suitable icon. Audit first: **the edit
actions were already wired in v0.2.0** (Renew / Quota x1.35 / Reset
traffic / Enable-Disable / Delete in client_detail_screen.dart, Add
client screen, panel_provider + client_actions + panel_api verified
vs 3x-ui source commit 85e2ded) — so this is v0.2.1, not v0.3.0.
Gates: `flutter analyze` clean, `flutter test` 53 passed.

### What was already working (v0.2.0, NOT rebuilt)
- All five client write actions + Add client + delete (keepTraffic=0,
  confirm dialogs), UUID preserved via GET-first update, quota x1.35
  rounds to whole GB, renew = remark dates + panel expiry = end + 1
  day 00:00 + reset traffic.
- SSH Setup tab + mistyroute-ctl forced commands + Sheets sync
  (still needs NayGyi's 5 Cloud Console OAuth steps).

### Fixed — UI glitches from the 23:15 phone screenshots
- Bandwidth card: the inbound name shared a Row with 3 chips, leaving
  it ~1 char wide (letters stacked vertically). Now the name has its
  own line, chips Wrap below.
- Client cards: `ListTile(isThreeLine: true)` fixed the tile height
  below the subtitle's real height, painting double/overlapping
  "Used" lines. Replaced with a custom Card + Column (no fixed
  height).
- Server Status header Row: title + Chip could overflow a narrow
  phone (206px in the 360px test — the test font measures wide; the
  real cause is two inflexible children). Title is now Expanded.
- Setup screen: the long public-key line is in a horizontal
  SingleChildScrollView (it is built in the IndexedStack even on the
  Dashboard tab).
- Narrow-phone (360px) widget test now passes: fling uses the real
  CustomScrollView, search field is scrolled back into view before
  typing (slivers unmount off-screen children), and the search
  assertion is scoped to the client Card (the typed query also
  matches find.text).

### New icon
- Dark teal (#0B2E35) icon: winding road into mist + shield + signal
  waves, no text. Source `icon-src/icon-1024.png`. Installed as
  Android launcher icon (all mipmap sizes + adaptive foreground /
  background + round), web PWA icons + favicon. App label
  "MistyRoute Manager".

### Renewal rule (NayGyi's correction)
- New period CONTINUES from the old remark end date, not today:
  `EiKay_15.10.26-15.11.26` + 1 month ->
  `EiKay_15.11.26-15.12.26`. If the old end is already past, start
  today instead (never backdate an already-over period). Panel expiry
  = new end + 1 day 00:00. SubId + UUID unchanged (GET-first).
- Remark format is exactly `Name_D.M.YY-D.M.YY` (dots in dates, one
  dash between, underscore after name, no zero-padding). Legacy
  single-date remarks normalise into this form on renewal
  (`MaNwe22.11.26` -> `MaNwe_22.11.26-22.12.26`, start = old end).
  `parseRemark` handles all live forms (pair/underscore, pair stuck
  to name, single date, bare name) without mangling names.

### Group filter (new)
- Group was missing from the model entirely. Verified vs 3x-ui v3:
  `Client.group` (`json:"group"`, gorm column `group_name`) comes
  from `GET /panel/api/clients/get/:email` — NOT from inbounds/list.
  Plumbed into `ClientInfo.group`, `ClientRecord.group`,
  `toClientJson` (always sent, so updates never wipe it),
  `buildCreatePayload`, `PanelProvider.addClient`.
- Dashboard chips: All groups (n) + one chip per group actually
  present (with counts) + Ungrouped (n) only when needed. Combines
  with search + flag filters; stale selection falls back to all.
  Live groups load in the background after the list (`_enrichGroups`,
  tolerant per-client failures). Demo data carries groups
  (MNA 8 / MayZin 10 / Friends 4 / FOC 1 / ungrouped 1).

### Add Client — Group field (NayGyi's spec)
- Only five fields: Name, Quota, Valid, IP limit, Group. Group is a
  dropdown of groups already present + "New group…" with a text
  field; blank = no group. Nothing else is asked for (remark dates,
  subId, flow, UUID, inbound derived automatically).

### Fix names — one tap (NayGyi's final design)
- Dashboard "Fix names (scope)" button fixes every fixable name in
  the selected group chip (or all groups); detail screen has a
  "Fix name" button for one client. NO preview/confirm dialog —
  after the run a results dialog lists fixed (old -> new) and
  skipped with reasons.
- Dates come from EXISTING data only, never invented:
  (1) the remark's own start+end pair, (2) panel expiryTime gives
  only an END date, never a start. A start that cannot be determined
  => skipped. Consequence: only pair-form remarks can be fixed
  (e.g. `EiKay15.10.26-15.11.26` -> `EiKay_15.10.26-15.11.26`);
  single-date (`MaNwe22.11.26`, `ZZWO_16.2.27`, `MAMS11.12.26`)
  and bare-name (`MaSandar-1`) remarks are ALWAYS skipped, even
  with a known panel expiry. SubId/UUID untouched (update goes
  through the fetched record).

### Billing (NayGyi's correction: VPS data is primary, DO optional)
- `lib/services/billing.dart`: estimate from the panel inbound
  "down" total (server->client = DO outbound) vs the 1 TB/month
  allowance, droplet $6.00/month prorated by day, overage $0.01/GiB,
  projected month-end at the current pace. Works WITHOUT a DO token;
  the estimate is never blocked by DO being unreachable.
- Dashboard Billing card shows TWO figures side by side: (1) Total
  DO cost (USD) and (2) Final AYA charge (MMK), plus the breakdown
  Base MMK (USD x 4,466.67) + 3% oversea fee = Final (USD x
  4,600.67), and the projected month-end pair. Labelled "Estimate
  from VPS data — panel counters are cumulative since the last
  traffic reset".
- AYA rates: base stored at statement precision (38,993.99 / $8.73)
  so the October bill reproduces exactly; 4,466.67 / 4,600.67 are
  its 2dp display roundings. Unit test: $8.73 -> base 38,993.99 +
  fee 1,169.82 = final 40,163.81 MMK.
- DO token is optional/secondary only: Settings has a DO token field
  (stored on-device, never in code) with in-app instructions
  (DO Control Panel > API > Generate New Token, read scope) and a
  "Check DO balance" button; the balance line appears on the
  Billing card when the check succeeds.

### SSH key constraint (NayGyi, standing for this release)
- Same package, same persistent debug keystore (same SHA-1), version
  bump only. No change to mistyroute-ctl or authorized_keys. The
  app's keypair lives in secure storage and survives an update
  install. ONLY an uninstall + reinstall generates a new keypair —
  that is the one case where the VPS line would need replacing.

### Delivery (v0.2.1, verified 2026-11-16)
- Gates: `flutter analyze` clean; `flutter test` **53 passed**
  (incl. the October AYA case, renewal/format/group/name-correction
  tests, and the 360px no-overflow test).
- APK: `MistyRoute_Manager-v0.2.1.apk`, 58,799,570 bytes,
  versionCode 3 / versionName 0.2.1, package
  `com.ngy.mistyroutemanager`, label "MistyRoute Manager",
  md5 `ac98b441751284761063d9951063d65f`, apksigner verified
  (v2 scheme), signer SHA-1
  `2A:F2:AC:97:7F:A8:9D:3C:01:9F:A7:61:BB:63:B4:4D:55:CF:CC:C6`
  — same keystore as v0.2.0, so an update install keeps the
  existing VPS SSH key working. Build took 394.5s.
- Drive: same AppDev folder as v0.2.0, file id
  `1a0OXqkN_124sLAB_4UkcHuMli6EjEoBD`, read back from Drive:
  name/size/md5 all match local.
- Web demo: https://ngy-reading-room.github.io/mistyroute-manager/
  (gh-pages commit `553fd15`, source commit `b856917`), served
  `main.dart.js` md5 `8b6bcddf0dd52d9c3d4b206f84fc530c` — identical
  to the local build, index HTTP 200. No Netlify credits used.
- NOT yet done: live-browser render check of the web demo
  (subagent has no live browser — parent to arrange) and NayGyi's
  phone test of the APK.

## v0.2.2+4 (2026-11-17) — Fix names for dateless remarks + Sheets sync A–F

NayGyi: "fix the dates even without a date in the name — draw the
data from the client expire date", plus "also fix Google Sheets sync"
(the app wrote the wrong 8-column format). Gates: `flutter analyze`
clean, `flutter test` **70 passed** (was 53 in v0.2.1).

### Date-derivation rule — VERIFIED against the real panel data, then implemented

The task's stated rule ("end = expiryTime minus 1 day") is WRONG
and was NOT used. Verified against the real Nov 16 panel JSON export
(24 clients, retrieved from the chat history with passwords redacted)
and against the live `vlesslist` sheet (read 2026-11-17):

- **updated_at DOES track the last edit for edited clients:**
  MaSandar-1/2 updated Nov 15 11:10/11:11 (= renewal date Nov 15),
  MAMS Nov 11 15:13 (= Nov 11 edit), ZZWO Nov 16 12:32 (=
  creation), MeMe Nov 12 06:54 (= Nov 12 quota extension),
  KoYeMin Nov 5 10:52, MaMar Nov 3 15:19.
- **BUT updated_at is a bulk stamp for never-edited-since-Nov-3
  clients:** `1793689936000` = 2026-11-03 13:42, identical for 10
  clients (bigsun, MaMee, MayZin, MayZinMom, MaNwe, MaMya,
  MaTheint, MaKyalSin, MTTM, MomMyatPwintFOC). It does NOT equal
  any renewal date for them — using it as a start date would be
  wrong (MaNwe would get 3.11.26 instead of 22.10.26). A shared
  updated_at is therefore never trusted
  (`bulkUpdatedAtValues` in client_actions.dart).
- **End date = the remark's own end date; the panel expiry's
  calendar date wins ONLY when it differs by more than 1 day**
  (a stale/typo remark). In the Nov 16 JSON, date(expiryTime)
  EQUALS the remark end for every single-date/bare client:
  MaSandar Feb 15 23:59 -> Feb 15, MAMS Dec 11 23:59 -> Dec 11,
  MaNwe Nov 22 23:59 -> Nov 22, MaMee Dec 3 23:59 -> Dec 3,
  EiKay Nov 15 00:00 -> Nov 15, MaTheint Oct 24 00:00 -> Oct 24,
  MaKyalSin Nov 26 00:00 -> Nov 26. Minus-1-day would give Feb 14
  / Dec 10 / Nov 21 — wrong for all of them. The two exceptions
  prove the >1-day rule: ZZWO (remark Feb 16, panel Jan 16, 31
  days apart -> panel wins, the known unresolved mismatch) and
  MTTM (remark Oct 29, panel Oct 30 00:00, 1 day apart -> remark
  wins, the panel's end+1-day convention). Pair remarks are
  unaffected (MaMar/Cecilion: expiry Dec 4 00:00, remark end
  Dec 3 — Fix names uses the remark dates).
- **Start date:** (1) pair remark -> the remark's start;
  (2) record never edited since creation (updated_at within a
  minute of created_at — ZZWO: 14 ms apart) -> the creation date;
  (3) trusted updated_at (unique across the loaded clients, not
  the creation time, before the end, within 3 calendar months of
  it, inclusive) -> that date; (4) otherwise the end date minus
  1 calendar month (the standard 1-month validity — verified
  against the live subIds: MaTheint 24.9.26, MTTM 29.9.26).
  ExpiryTime 0 (bigsun, MomMyatPwintFOC) -> skipped.
- **Verified results:** MaSandar-1 -> `MaSandar-1_15.11.26-15.2.27`;
  MAMS -> `MAMS_11.11.26-11.12.26`; MaNwe -> `MaNwe_22.10.26-22.11.26`;
  ZZWO -> `ZZWO_16.11.26-16.1.27`; KoYeMin -> `KoYeMin_5.11.26-2.12.26`;
  MaMee -> `MaMee_3.11.26-3.12.26`; MaTheint -> `MaTheint_24.9.26-24.10.26`;
  MaKyalSin -> `MaKyalSin_26.10.26-26.11.26`; MTTM -> `MTTM_29.9.26-29.10.26`.
- Implementation: `planNameCorrection` in client_actions.dart now
  takes named `updatedAtMs` / `createdAtMs` /
  `sharedUpdatedAtMs`; `remarkEndDate` (end rule) and
  `dateOfEpochMs` are shared with the Sheets sync. `ClientRecord`
  parses `created_at` / `updated_at`; `ClientInfo` carries `subId`
  + both timestamps; the provider's `_enrichClientDetails`
  (renamed from `_enrichGroups`) fills group + subId + timestamps
  from the per-client records. `_applyNameFix` fetches the record
  first when the remark has no start and the timestamps are not
  loaded yet — planning from the 1-month fallback without checking
  the record could pick the wrong start (MaSandar's trusted Nov 15
  vs the Jan 15 fallback). Demo data mirrors the real patterns
  (trusted edit, shared bulk stamp, never-edited record) so all
  three start-date paths are previewable in demo mode.

### Sheets sync — rewritten to the real `vlesslist` A–F format

- **The v0.2.1 sync was broken two ways:** (1) it wrote the wrong
  columns (Name / Inbound / Status / Used GB / Quota GB / Used % /
  Expiry / Days left) instead of the sheet's A–F (Name |
  Subscription URL | Config | Expire Date | Group | Remark);
  (2) it wrote to a tab called `vlesslist` — but the spreadsheet
  named `vlesslist` (ID `15XUOcPg0PT6uveYInKtf9NlcZhx9RZPeYMlHOl66cW4`)
  has exactly ONE tab, named `Sheet1` (verified via the Sheets API
  2026-11-17), so every v0.2.1 sync would 404. `sheetsTabName` is
  now `Sheet1`.
- **Row mapping:** Sub URL =
  `https://ngylab.cloud-ip.cc:2096/ngylab_sub/<subId>` with the
  panel's REAL subId (from the per-client record — EiKay's is
  `8pt4xbd1kpors3rv`, not `EiKay`); Config = the fresh vless://
  link fetched from that sub URL (base64-decoded; a failed fetch
  keeps the existing Config cell, never blanks it); Expire Date =
  the remark end date as ISO yyyy-MM-dd (same end rule as Fix
  names); Group = the panel group; Remark = the full remark.
  No-expiry clients write `∞`, matching the live sheet.
- **Sync behaviour:** the sheet is READ first, existing rows are
  updated in place (matched by Name, then by the subId in the
  Subscription URL; the sheet's row order is kept), genuinely new
  clients are appended, rows for clients no longer in the panel
  are left untouched and reported — never deleted. One merged PUT
  of the read-back matrix, never a blind wipe. If any row has
  content beyond column F, the sync aborts without writing.
  Ragged rows (Sheets omits trailing empty cells) are padded.
- **Panel-date safeguard:** when the existing Expire Date cell
  holds a date that differs from the computed one AND equals the
  panel expiry's calendar date, the existing cell is kept and
  reported (live cases: ZZWO 2027-01-16, MTTM 30-10-26 — the
  sync must not silently regress panel truth). Verified: the new
  rule reproduces every Expire Date in the live sheet exactly.
- **Setup path:** the Sheets card now shows the one-time Cloud
  Console steps on demand ("Show one-time setup steps") as well
  as after a failed sign-in, and sync errors are surfaced with
  actionable text (404 = wrong ID/tab, 401/403 = sign in again /
  share the sheet). The steps live in `sheetsSetupSteps()` in
  sheets_sync_service.dart; `GoogleSignInService` moved to its
  own file (`google_sign_in_service.dart`) unchanged.
- **Demo-mode guard:** `PanelProvider.syncSheets` refuses to sync
  while demo data is on — syncing sample clients would overwrite
  the real sheet. (v0.2.1 had no such guard.)
- Tests: 17 new/rewritten Sheets tests (A–F mapping, in-place
  update, append, orphans kept, panel-date safeguard, config
  fetch success/failure, read 404, beyond-column-F abort,
  ragged rows) with a fake HTTP client — the real spreadsheet is
  never touched by tests.

### What the app now does vs what NayGyi still has to do himself

- **The app now does:** Fix names for dateless remarks (from
  panel data); Sheets sync in the real A–F format with in-place
  update + append + fresh Config links + the panel-date
  safeguard; demo-mode sync refusal; visible setup steps and
  helpful sync errors.
- **NayGyi still has to do himself (one-time Cloud Console
  setup, the app cannot do it):** (1) in console.cloud.google.com,
  enable the Google Sheets API in the project that owns the
  `vlesslist` spreadsheet; (2) create the Android OAuth client ID
  for package `com.ngy.mistyroutemanager` with SHA-1
  `2A:F2:AC:97:7F:A8:9D:3C:01:9F:A7:61:BB:63:B4:4D:55:CF:CC:C6`;
  (3) put `google-services.json` in `android/app/` and rebuild
  the APK; (4) share the `vlesslist` spreadsheet with the Google
  account he signs in with, as Editor. Until then, sign-in throws
  `SheetsSetupNeeded` and the app shows these exact steps.

### Delivery (v0.2.2, verified 2026-11-17)
- Gates: `flutter analyze` clean; `flutter test` **70 passed**
  (was 53 in v0.2.1 — 17 new/rewritten: Fix-names date derivation
  for the exact real-panel cases, Sheets A–F mapping / in-place
  merge / append / safeguard / ragged rows).
- APK: `MistyRoute_Manager-v0.2.2.apk`, 58,881,490 bytes,
  versionCode 4 / versionName 0.2.2, package
  `com.ngy.mistyroutemanager`, label "MistyRoute Manager",
  md5 `3c82488ff7a2134aa30ceb59beccdfa8`, apksigner verified
  (v2 scheme), signer SHA-1
  `2A:F2:AC:97:7F:A8:9D:3C:01:9F:A7:61:BB:63:B4:4D:55:CF:CC:C6`
  (keystore SHA-256 matches the APK signer cert) — same keystore
  as v0.2.0/v0.2.1, so an update install keeps the existing VPS
  SSH key working. Build took 444.8s.
- Drive: same AppDev folder as v0.2.0/v0.2.1, file id
  `1Eo-xKDUhpvILlmBoENBWzfeMOS76jqTk`, read back from Drive:
  name/size/md5 all match local.
- Web demo: https://ngy-reading-room.github.io/mistyroute-manager/
  (gh-pages commit `f1b4fec`, source commit `14a050b`), served
  `main.dart.js` md5 `8e2f555990bf52dfbac6c238a8d1ff5b` — identical
  to the local build (rebuilt deterministically: two builds gave
  the same md5), index HTTP 200. No Netlify credits used.
- Deploy lesson (2026-11-17): the first gh-pages deploy attempt
  DELETED the whole local `build/` directory (including the APK
  copy — the Drive upload had already succeeded, so nothing was
  lost). Cause: `rsync -a --delete build/web/ ./` with the source
  nested INSIDE the destination — rsync's --delete removed `build/`
  from the destination while the transfer was reading it ("file
  has vanished"). NEVER rsync a build output into its own parent
  with --delete. The working method: `git worktree add
  /tmp/mrm-ghpages gh-pages`, rsync into the worktree, commit +
  push there, `git worktree remove`. The web build was then
  rebuilt (same md5) and deployed that way.
- NOT yet done: live-browser render check of the web demo
  (subagent has no live browser — parent to arrange) and NayGyi's
  phone test of the APK (install as an UPDATE over v0.2.1, test
  writes on a test client first, then Fix names + Sheets sync).
