# ADR 0005 — One client per brand behind `TVController`

- Status: accepted
- Date: 2026-10-29
- Evidence: docs/PROTOCOL.md § 11.5, § 12.4

## Context

The user also has a Sony BRAVIA (KD-49X755F) on the LAN. Its API (JSON-RPC and IRCC on
port 80, PIN pairing with a cookie) has nothing in common with the Samsung WebSockets.
`AppModel` called `SamsungTVClient` directly.

## Decision

- `TVController` (actor protocol) holds what every brand does: pair, keys, text, power off,
  wake from standby. `SamsungTVClient` and `SonyTVClient` conform.
- `TVDevice.brand` picks the client; nil (saved before this change) means Samsung.
- The UI and presets keep Samsung `KEY_*` codes. `SonyPayloads.commandName` maps them to
  IRCC names, so presets work on both brands.
- Catalogue apps launch on Sony by title match against `getApplicationList`.
- Brand-only features stay on the concrete client (`samsungClient(for:)` for Art Mode).
- The saved Sony PIN goes in `TokenStore`, like the Samsung token.

- Sony and LG list apps by title: `NamedAppLauncher` adds `findApp`/`launchApp(named:)`/`launch(id:)`,
  and `TVAppEntry.match` maps catalogue names to TV titles for both.
- LG (`LGTVClient`, SSAP over wss 3001) saves its `client-key` in `TokenStore` too.

## Consequences

- LG was added as the third brand with no change to the views or presets.
- Discovery probes each host on up to three ports (8001, 80, 3001).
