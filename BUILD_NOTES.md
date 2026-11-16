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
