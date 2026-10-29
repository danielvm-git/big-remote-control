# ADR 0002 — Power on/off on The Frame

- Status: accepted
- Date: 2026-10-29
- Evidence: specs/verifications/VERIFY-2026-10-29-frame43.md

## Context

Live tests on the 43" Frame (QN43LS03D, 2024):

- `KEY_POWER` Press/Release over the remote channel acts as a click (TV ↔ Art) for 3 s and 5 s holds.
- `KEY_POWEROFF` is ignored. IP Control port 1516 is closed.
- In standby the REST API still answers (`PowerState: standby`) and a `KEY_POWER` click turns the TV on.
- Wake-on-LAN (wired) did not wake it within 30 s.

## Decision

- **Off:** SmartThings `switch off` when configured. Without SmartThings a Frame goes to
  Art Mode and the app says why. Non-Frame TVs keep the plain `KEY_POWER` click.
- **On:** `KEY_POWER` click when REST reports standby; then WOL and SmartThings `switch on` as fallbacks.

## Consequences

- No LAN-only real power-off on this model. Revisit if "IP Remote" becomes available.
