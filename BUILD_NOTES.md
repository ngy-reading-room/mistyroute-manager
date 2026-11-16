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
