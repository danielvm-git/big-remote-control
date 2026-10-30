# ADR 0006 — iPhone app shares the Mac sources

- Status: accepted
- Date: 2026-10-29

## Context

The user wants an iPhone app on TestFlight. ADR 0001 says the phone must never be a
requirement: the iPhone app is one more controller, not a bridge. Every TV client, the
`AppModel` and most views are plain Foundation/SwiftUI.

## Decision

- New XcodeGen target `BigRemoteiOS` (iOS 18, iPhone, bundle `com.danielvm.BigRemoteiOS`) compiles
  `Sources/BigRemote` minus the macOS entry point and the macOS-only windows, plus `Sources/BigRemoteiOS`
  (tabs: Controle, Presets, TVs).
- macOS-only code sits behind `#if os(macOS)`: `NSWorkspace` calls and the ARP routing-table read.
- Each device pairs on its own (Samsung token, Sony PIN with client id `BigRemote:iphone`, LG key).
- Presets are edited on the Mac; the iPhone runs its own copy (no sync yet).
- `scripts/testflight.sh` archives with automatic signing and uploads with `xcodebuild -exportArchive`
  (`destination: upload`). The build number is the UTC time.
- The app icon is drawn from plain shapes (`scripts/render-app-icon.swift`): the SF Symbols license
  forbids symbols in app icons.

## Consequences

- iOS blocks UDP broadcast without the `com.apple.developer.networking.multicast` entitlement (Apple
  must approve it). Wake-on-LAN from the iPhone only sends the unicast packet, which a sleeping TV
  may not get. Samsung (KEY_POWER in standby) and Sony (`setPowerStatus`) wake over TCP and are not affected.
- The ARP cache is not readable on iOS: the MAC is typed by hand on the iPhone.
- Preflight also builds the iOS target unsigned, so CI catches iOS compile errors.
