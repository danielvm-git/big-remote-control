# Test plan — Big Remote

## Automated (Preflight, every change)

| Suite | File | Stories |
|-------|------|---------|
| Remote channel payloads, channel events | `Tests/BigRemoteTests/RemotePayloadTests.swift` | e01s01 e01s02 e01s03 e02s01 |
| Art channel payloads | `Tests/BigRemoteTests/ArtPayloadTests.swift` | e03s01 e03s02 |
| Wake-on-LAN, network addresses, device info | `Tests/BigRemoteTests/NetworkTests.swift` | e04s01 e07s01 |
| Presets | `Tests/BigRemoteTests/PresetTests.swift` | e05s01 |
| SmartThings, JSONValue | `Tests/BigRemoteTests/SmartThingsTests.swift` | e06s01 |

Tests compile only `Models/` and `Services/Protocol/`: no app host, no network, no TV.

## Manual (UAT on a real TV, user present)

Record each session in `specs/verifications/VERIFY-<date>-<tv>.md`.
Ask before any state-changing command. Read-only `GET :8001` needs no approval.

| Check | Expected |
|-------|----------|
| Pair | TV prompt appears; token saved |
| Volume up/down | Volume OSD on screen |
| Launch YouTube | `GET /api/v2/applications/111299001912` → `visible: true` |
| Art on/off | `get_artmode_status` matches |
| Power on from standby | REST `standby` → `on` within ~6 s |
