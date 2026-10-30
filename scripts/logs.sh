#!/usr/bin/env bash
# story: e12s02
# Reads the app logs (JSON lines written by Sources/BigRemote/Services/Log.swift).
#
#   scripts/logs.sh setup        create logs-pulled/ and ignore it in git (safe to repeat)
#   scripts/logs.sh mac          follow today's Mac log
#   scripts/logs.sh iphone       copy the iPhone logs to logs-pulled/iphone (USB, dev-signed build)
#   scripts/logs.sh pairing [dir ...]   token and connect events in time order (default: both folders)
#   scripts/logs.sh path         where each log lives
#
# Logs hold IPs and TV ids, never tokens, PINs or cookies (only short fingerprints).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DIR="$HOME/Library/Containers/com.danielvm.BigRemote/Data/Library/Application Support/BigRemote/logs"
PULLED="$ROOT/logs-pulled"
IOS_BUNDLE="com.danielvm.BigRemoteiOS"

cmd_setup() {
  mkdir -p "$PULLED"
  if ! grep -qx 'logs-pulled/' "$ROOT/.gitignore" 2>/dev/null; then
    echo 'logs-pulled/' >> "$ROOT/.gitignore"
    echo "Added logs-pulled/ to .gitignore"
  else
    echo "logs-pulled/ already ignored"
  fi
}

latest_mac_file() {
  find "$MAC_DIR" -name 'bigremote-*.jsonl' 2>/dev/null | sort | tail -1
}

cmd_mac() {
  local file
  file="$(latest_mac_file)"
  [ -n "$file" ] || { echo "No Mac log yet. Open Big Remote once. Looked in: $MAC_DIR" >&2; exit 1; }
  echo "Following $file"
  tail -n 40 -f "$file"
}

cmd_iphone() {
  cmd_setup >/dev/null
  local device="${DEVICE:-}"
  if [ -z "$device" ]; then
    device="$(xcrun devicectl list devices 2>/dev/null \
      | awk '/physical/ && /connected|available/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) { print $i; exit } }')"
  fi
  [ -n "$device" ] || { echo "No iPhone found. Plug it in, unlock it, or set DEVICE=<udid>." >&2; exit 1; }
  mkdir -p "$PULLED/iphone"
  xcrun devicectl device copy from --device "$device" \
    --domain-type appDataContainer --domain-identifier "$IOS_BUNDLE" \
    --source "Library/Application Support/BigRemote/logs" --destination "$PULLED/iphone" >/dev/null
  echo "Copied to $PULLED/iphone:"
  find "$PULLED/iphone" -name 'bigremote-*.jsonl' | sort
}

cmd_pairing() {
  local dirs=("$@")
  if [ "${#dirs[@]}" -eq 0 ]; then dirs=("$MAC_DIR" "$PULLED/iphone"); fi
  python3 -I - "${dirs[@]}" <<'PY'
import json, pathlib, sys
rows = []
for d in sys.argv[1:]:
    for f in pathlib.Path(d).rglob("bigremote-*.jsonl"):
        for line in f.read_text().splitlines():
            try:
                rows.append(json.loads(line))
            except ValueError:
                pass
keep = ("token.", "remote.connect", "art.connect", "pair.", "sony.", "lg.connect", "lg.register", "link.changed", "app.start")
rows = [r for r in rows if r["message"].startswith(keep)]
rows.sort(key=lambda r: r["ts"])
for r in rows:
    fields = " ".join(f"{k}={v}" for k, v in sorted(r["fields"].items()))
    print(f'{r["ts"][5:23]} {r["device"]:4} {(r.get("tv") or "-")[:22]:22} {r["message"]:26} {fields}')
if not rows:
    print("No pairing events found.", file=sys.stderr)
PY
}

cmd_path() {
  echo "Mac:    $MAC_DIR"
  echo "iPhone: $IOS_BUNDLE container, Library/Application Support/BigRemote/logs (scripts/logs.sh iphone)"
  echo "Pulled: $PULLED"
  echo "Console.app / log stream: subsystem com.danielvm.BigRemote"
}

case "${1:-}" in
  setup) cmd_setup ;;
  mac) cmd_mac ;;
  iphone) cmd_iphone ;;
  pairing) shift; cmd_pairing "$@" ;;
  path) cmd_path ;;
  *) sed -n '2,13p' "${BASH_SOURCE[0]}"; exit 2 ;;
esac
