# MistyRoute Manager

Flutter management app for a 3x-ui (Xray) VPN panel — dashboard, client
write actions, SSH tunnel controls, and Google Sheets sync.

- **Dashboard:** bandwidth totals, live server status, flags (≥80% quota,
  expiring ≤7d, disabled), client list, client details.
- **Write actions (v0.2):** add client, renew (new remark dates + reset
  traffic), extend quota ×1.35, reset traffic, enable/disable, delete.
  In demo mode the actions apply to sample data and say so.
- **Setup (v0.2, Android only):** the app's own SSH keypair + one-tap
  tunnel actions (SSH Connect, Check Tunnel Link, Tunnel Restart,
  Tunnel Status) through the forced-command script
  `scripts/mistyroute-ctl` on the VPS.
- **Google Sheets sync (v0.2):** panel → `vlesslist` tab, ISO dates.
  Needs the one-time Google Cloud OAuth setup (see BUILD_NOTES.md).

## Live vs demo

- **Demo data** is the default: 24 fictional clients, clearly labelled.
- **Live data** needs the panel URL + API token in Settings (stored
  on-device only, never in the repo) and the Android APK — the web demo
  cannot reach the panel because the panel sends no CORS headers.
- Auth is API-token-only. No username/password/2FA fields exist anywhere.

## Links

- Demo: https://ngy-reading-room.github.io/mistyroute-manager/
- Repo: https://github.com/ngy-reading-room/mistyroute-manager
- Build notes (versions, verification, what needs the user):
  [BUILD_NOTES.md](BUILD_NOTES.md)

## Build

- Flutter 3.47.9, JDK Temurin 17 (see `~/workspace/tools/`).
- APK: `~/workspace/tools/build-apk-mistyroute.sh release`
  (debug-signed with the persistent keystore in
  `~/workspace/tools/android-debug.keystore`).
- Web: `flutter build web --release --base-href /mistyroute-manager/`
  then push `build/web` to the `gh-pages` branch.
- Tests: `flutter test` — write-action request building (fake HTTP),
  renewal/quota math, SSH command building, Sheets rows.
