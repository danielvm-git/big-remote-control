# Security review: feat/observability vs main

- Stamp: reviewed HEAD `11e7bde`, diff `git diff main...11e7bde` (63 files before the fix commit)
- Scope: TLS trust for LAN TVs, pairing tokens/PINs/cookies, secrets in the structured log, Sony and LG
  transports, the diagnostics export, the iOS app storage.
- Threshold: findings below confidence 8 are suppressed from the gate (listed for information only).
- Result: **no open HIGH finding with confidence ≥ 8.** The one that qualified was fixed in `11e7bde`.

## Findings

### F1 — HIGH — secrets in logs (CWE-328, CWE-359) — confidence 9 — FIXED in 11e7bde
- `File:Line`: `Services/Protocol/LogEntry.swift` (`LogRedactor.fingerprint`), `SonyTVClient.swift` (PIN
  fields), `docs/PROTOCOL.md` (four committed fingerprints).
- Manifestation: the log stored `SHA-256(secret)[0..4]` for Samsung tokens (8 digits) and Sony PINs (4 digits).
  With the log, an attacker enumerates 10^8 or 10^4 candidates offline and recovers the value. A Samsung token
  controls the TV; a Sony PIN is the credential of its REST API.
- Exploit path: a shared diagnostics file, or a copy of the app container, leaks the log; the attacker recovers
  the token and then drives the TV over the LAN.
- Fix: fingerprints are HMAC-SHA256 under a per-device 256-bit key kept in UserDefaults; the Sony PIN is
  never logged; the committed doc holds no fingerprints. Test `fingerprintNeedsTheDeviceKey` checks the key
  dependence and that the plain hash is not produced. ADR 0007 updated.
- Residual: device logs written before the fix still hold the old unkeyed fingerprints. They stay on the
  devices (not committed; `logs-pulled/` removed from the workspace). Delete them with the app data.

### F2 — MEDIUM — plain HTTP to the Sony TV (CWE-319) — confidence 8 — ACCEPTED, not fixable on the TV side
- `Services/SonyRESTClient.swift`, `Services/Protocol/SonyPayloads.swift`: `http://<ip>/sony/*` carries the PIN in
  `Authorization: Basic` and the `auth` cookie in clear.
- Exploit path: a device on the same Wi-Fi with sniffing reads the PIN and cookie and can call the TV's API.
- Decision: the BRAVIA REST API offers no TLS on port 80. Recorded as a known limit in `docs/PROTOCOL.md` § 11.
  Mitigation for the user: keep Sony on a trusted network, and forget the pairing if a device is lost.

### F3 — MEDIUM — any self-signed certificate accepted on private IPs (CWE-295) — confidence 7 — SUPPRESSED, follow-up
- `Services/LANTrustDelegate.swift` (pre-existing, not in this diff): accepts any server certificate for any
  10/8, 172.16/12 or 192.168/16 host, with no pinning.
- Exploit path: a hostile device on the LAN answers as a TV, receives the Samsung token or the Sony cookie.
- Recommendation (follow-up, not this merge): pin each TV's certificate on first use and store its fingerprint
  next to the token; reject a changed certificate with a logged warning.

### F4 — LOW — diagnostics export left in the temporary folder (CWE-200) — confidence 8 — ACCEPTED
- `Services/Log.swift` `exportURL()` writes `bigremote-logs.jsonl` into the temp directory and never deletes it.
- The file holds IPs and TV ids, no secrets (after F1). Recommendation: delete it after the share sheet closes.

### F5 — LOW — pairing tokens and the Sony PIN in UserDefaults (CWE-922) — confidence 7 — SUPPRESSED, pre-existing
- `Services/TokenStore.swift`: plain UserDefaults, by design (its comment: Keychain prompts on rebuilds). The
  Sony PIN is stored there as the token. Recommendation (follow-up): move the iOS side to the Keychain.

### F6 — LOW — redaction covers `key=value` only (CWE-532) — confidence 6 — SUPPRESSED
- `LogRedactor.scrub` masks `token=`, `auth=`, `pin=`, `psk=`. A JSON-style `"token":"…"` in an error text would pass.
  No current call site produces that; keep it in mind when adding error logging.

## Checked and clean
- No LAN IPs or real MACs in tracked files (MACs are `02:…` examples).
- No `http://`/`ws://` outside the Sony REST path and the local-networking ATS exception.
- Log writes: `text.send` logs the length only, never the text.
- Every field goes through `LogRedactor.scrub`; secret field names are replaced by `<redacted>`.
- Logs are JSON-encoded, so a newline in a TV reply cannot forge a log line.
