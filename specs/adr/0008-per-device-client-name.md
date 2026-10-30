# ADR 0008 — One Samsung client name per device, no background art retries

- Status: accepted
- Date: 2026-10-29
- Evidence: structured log (ADR 0007), `scripts/logs.sh pairing` on 2026-10-29

## Context

The TVs kept asking to pair. The first log capture showed the Mac and the iPhone holding different tokens for
the same Frame while both connected as "Big Remote", and the iPhone's art socket failing every ~15 s with its
token. A Samsung TV binds a token to the client name, so the last device to pair wins and the other one keeps
connecting with a stale token. Background art monitoring retried those connects (each can raise a prompt).

## Decision

- `RemotePayloads.clientName` is "Big Remote (Mac)" on macOS and "Big Remote (iPhone)" on iOS.
- Samsung tokens are stored under `TokenStore.samsungKey`: TV id plus client name. Old tokens (key = TV id)
  are no longer read, so each device shows "not paired" once and pairs again under its own name.
- A failed art-socket open sets `artAutoPaused`: background monitoring stops until a remote or art connect
  succeeds or the pairing is forgotten. User actions (Arte, TV) still try.

## Consequences

- One extra pairing prompt per device after the update, then one entry per device in the TV's device list.
- Art Mode status stays "unknown" after a failure until the next successful command or Parear.
