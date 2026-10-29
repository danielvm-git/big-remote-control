# Verification — 43" Frame (QN43LS03D, 2024), 2026-10-29

Device: `smarttv-samsung-43`, 192.168.1.21, wired, api/v2 2.0.25, Tizen, pt_BR.
Operator: owner at the TV with the physical remote. Driver: stdlib WebSocket script
mirroring the app payloads, then the app itself.

| # | Action | Result | Story |
|---|--------|--------|-------|
| 1 | Pair (remote channel, name "Big Remote") | First attempts timed out (prompt closes fast); accepted on retry, token issued | e01s01 ✅ |
| 2 | `KEY_VOLUP`, `KEY_VOLDOWN` | Volume OSD shown | e01s02 ✅ |
| 3 | `get_artmode_status` (art channel, same token) | `off`; later `on` | e03s01 ✅ |
| 4 | App buttons in the menu bar app | Owner confirmed keys work | e01s02 ✅ |
| 5 | `ed.apps.launch` YouTube (WS) | No reply, `visible:false` | e02s01 ❌ → ADR 0003 |
| 6 | `POST /api/v2/applications/111299001912` | `visible:true`; owner confirmed apps open from the app | e02s01 ✅ |
| 7 | `KEY_POWER` hold 3 s / 5 s | Click only: TV ↔ Art | e04s02 → ADR 0002 |
| 8 | `KEY_POWEROFF` | Ignored | e04s02 |
| 9 | Port 1516 (IP Control) | Closed | e04s02 |
| 10 | WOL (wired MAC, 3 rounds, ports 9/7) | Stayed `standby` 30 s | e04s01 ❌ |
| 11 | `KEY_POWER` click in standby | `on` in ~6 s | e04s01 ✅ |
| 12 | `ed.installedApp.get` | TV closes the socket | e02s01 (use per-ID GET) |

Installed app IDs confirmed: see `docs/PROTOCOL.md` § live test results.
Not covered: 32" Frame (other room), SmartThings (no token), text input.
