# ADR 0003 — Launch apps with REST first

- Status: accepted
- Date: 2026-10-29
- Evidence: specs/verifications/VERIFY-2026-10-29-frame43.md

## Context

On the 2024 Frame `ed.apps.launch` over the remote channel gets no reply and the app
stays `visible: false`. The send never fails, so a WS-first strategy never fell back.
`POST /api/v2/applications/<id>` made YouTube visible.

## Decision

`SamsungTVClient.launchApp` uses REST `POST` first and the WS `ed.apps.launch` only
when REST fails (native IDs unknown to REST).

## Consequences

- App IDs are resolved per TV with `GET /api/v2/applications/<id>` (404 = not installed).
