# Security plan — Big Remote

| Asset | Threat | Control |
|-------|--------|---------|
| TV pairing tokens | Read by other apps | Stored per TV in the app's sandboxed UserDefaults; LAN-only value. |
| SmartThings token | Leak | Keychain only; never logged or shown in banners. |
| TLS to TV (self-signed) | MITM / trust widening | `LANTrustDelegate` accepts self-signed certs only for private IPv4 hosts. |
| TV state | Destructive keys | `KEY_FACTORY` blocked; no automation near Factory Reset / Reset Smart Hub / DNS. |
| CI release | Supply chain | big-release binary pinned by version and SHA-256; first-party actions by major tag. |
| Commits | Attribution policy | CI blocks `Co-authored-by` footers. |
