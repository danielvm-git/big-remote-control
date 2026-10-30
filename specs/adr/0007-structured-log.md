# ADR 0007 — Structured JSON log in both apps

- Status: accepted
- Date: 2026-10-29

## Context

Both TVs asked to pair again after being paired, and the apps logged nothing (one `NSLog` for presets). Mac and
iPhone also introduce themselves to a Samsung TV with the same client name ("Big Remote"), so one device may
invalidate the other's token. Without a record there was no way to tell.

## Decision

- `Log.info/warning/error/debug(category, message, tv:, fields)` writes one JSON line per event to
  `Application Support/BigRemote/logs/bigremote-YYYYMMDD-NN.jsonl` and mirrors it to `os.Logger`.
  An `AsyncStream` feeds one writer task, so call sites never block and entries stay ordered.
- Format, redaction and file naming are pure and unit-tested (`Services/Protocol/LogEntry.swift`).
- Secrets: fields named token/pin/clientKey/cookie/auth/psk are replaced by `<redacted>`; `token=`, `auth=`,
  `pin=`, `psk=` inside text (socket URLs in error messages) are masked. Tokens are logged only as an 8-hex
  HMAC-SHA256 fingerprint under a per-device key (UserDefaults `logFingerprintKey`), enough to see that one
  changed. A plain hash would be reversible: Samsung tokens are 8 digits. Sony PINs (4 digits) are never logged.
- `TokenStore.setToken` logs every write and clear with its caller (`#fileID:#line`), old and new fingerprint.
- Instrumented: connect, pairing and close paths of the Samsung (remote and art), Sony and LG clients; commands
  (keys, apps, text length, power); link and reachability transitions; app start; user-visible banners and errors.
- Read it with `scripts/logs.sh` (Mac follow, iPhone copy over USB, pairing timeline) or the in-app Diagnóstico
  section (Share on iPhone, Finder on the Mac).

## Consequences

- Logs hold IPs and TV ids; they are never committed (`logs-pulled/` is ignored).
- Polling is logged only when reachability changes, so a TV that is off does not flood the file.
- Retention: 14 files, 5 MB each at most.
