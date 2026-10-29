# ADR 0001 — LAN-first, the phone is never a requirement

- Status: accepted
- Date: 2026-10-29

## Context

The owner uses the SmartThings phone app to control the TVs. The goal is to keep
working when the phone is away or out of battery. The reference project
(glass-home-samsung-tv) used a phone as a camera; that is not wanted here.

## Decision

All core features talk directly from the Mac to the TV over the LAN:
remote channel (WSS 8002), art channel (WSS 8002), REST (HTTP 8001), Wake-on-LAN.
SmartThings is optional and reached from the Mac over the internet, never via the phone.

## Consequences

- Real power-off on the 2024 Frame needs SmartThings (see ADR 0002).
- Picture/sound/input by name need SmartThings (no LAN API on these models).
