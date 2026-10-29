# Tech stack — Big Remote

## Stack

| Layer | Choice |
|-------|--------|
| Language | Swift 6 (strict concurrency `complete`) |
| UI | SwiftUI `MenuBarExtra` + `Window` + `Settings` scenes |
| Platform | macOS 15+, App Sandbox (`network.client`), hardened runtime |
| Project | XcodeGen (`project.yml` → `BigRemote.xcodeproj`, not committed) |
| Networking | `URLSessionWebSocketTask` (WSS 8002), `URLSession` (REST 8001), BSD UDP socket (WOL) |
| Tests | Swift Testing (`@Suite`, `#expect`), no test host, no network |
| Lint | SwiftLint (`.swiftlint.yml`), yamllint, shellcheck |
| CI/CD | GitHub Actions `ci-cd.yml` (template `ci-cd-swift.yml` v2.0.0) + big-release |
| Dependencies | none (Foundation, Network, SwiftUI) |

## Module map

```
Sources/BigRemote/
├── App/            AppModel (+Remote, +Power, +TVList, +Presets, +SmartThings), BigRemoteApp
├── Models/         TVDevice, DeviceInfo, TVApp, RemoteKey, Preset, JSONValue, TVStatus
├── Services/
│   ├── Protocol/   Pure payload builders/parsers (compiled into the test bundle)
│   ├── SamsungTVClient(+Art)   actor: remote + art channels per TV
│   ├── ChannelSocket           actor: one WebSocket, hard-deadline handshake
│   ├── TVRESTClient, TVDiscovery, ARPTable, WakeOnLANSender
│   ├── SmartThingsClient, KeychainStore, TokenStore, Persistence
│   └── LANTrustDelegate        self-signed TLS trust, private IPv4 only
└── Views/          Menu bar remote, main window, settings, preset editor
```

## Data flow

View → `AppModel` (main actor) → `SamsungTVClient` actor → `ChannelSocket` / `TVRESTClient` → TV.
TV events flow back as `TVClientUpdate` into `AppModel.statuses`.
REST polling every 7 s is read-only and never opens a socket.

## Protocol reference

`docs/PROTOCOL.md` — endpoints, payloads, live test results per model.

## Domain language

See `specs/product/GLOSSARY_LATEST.yaml`.
