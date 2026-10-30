#!/usr/bin/env bash
# story: e08s01
# Preflight — the full local verification stack (AGENTS.md § Commands).
# macOS: SwiftLint (strict) + XcodeGen + build + tests + portable checks.
# Linux (CI verify job): portable checks only; macOS steps print [SKIP].
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
PASS=0
FAIL=0

run_check() {
  local name="$1"; shift
  echo "--- $name ---"
  if "$@"; then PASS=$((PASS + 1)); else echo "FAIL: $name"; FAIL=$((FAIL + 1)); fi
}

check_agent_symlinks() {
  [ "$(readlink CLAUDE.md)" = "AGENTS.md" ] && [ "$(readlink GEMINI.md)" = "AGENTS.md" ]
}

check_agents_filled() {
  ! grep -q '\[One sentence' AGENTS.md
}

check_specs_yaml() {
  python3 -I -c '
import sys, pathlib
try:
    import yaml
except ImportError:
    print("[SKIP] PyYAML not installed"); sys.exit(0)
for path in sorted(pathlib.Path("specs").rglob("*.yaml")) + [pathlib.Path(".big-release.yml"), pathlib.Path(".swiftlint.yml")]:
    yaml.safe_load(path.read_text())
print("specs YAML parses")
'
}

check_no_generated_files() {
  ! git ls-files --error-unmatch BigRemote.xcodeproj >/dev/null 2>&1 \
    && ! git ls-files | grep -qE '^(build|DerivedData)/'
}

echo "==> Preflight: Big Remote"
run_check "agent symlinks" check_agent_symlinks
run_check "AGENTS.md filled" check_agents_filled
run_check "specs YAML" check_specs_yaml
if git rev-parse --git-dir >/dev/null 2>&1; then
  run_check "no generated files tracked" check_no_generated_files
fi
if command -v yamllint >/dev/null 2>&1; then
  run_check "yamllint" yamllint .github/workflows .big-release.yml .swiftlint.yml .yamllint specs
else
  echo "[SKIP] yamllint not installed (pip install yamllint)"
fi
if command -v shellcheck >/dev/null 2>&1; then
  run_check "shellcheck" shellcheck scripts/*.sh
else
  echo "[SKIP] shellcheck not installed"
fi

if [ "$(uname -s)" = "Darwin" ]; then
  run_check "swiftlint" swiftlint lint --strict --quiet
  run_check "xcodegen" xcodegen generate --quiet
  run_check "build + test" xcodebuild -scheme BigRemote -destination 'platform=macOS' \
    -derivedDataPath build -quiet test
  # Unsigned device build: catches iOS-only compile errors without a team or simulator.
  run_check "iOS build" xcodebuild -scheme BigRemoteiOS -destination 'generic/platform=iOS' \
    -derivedDataPath build -quiet CODE_SIGNING_ALLOWED=NO build
else
  echo "[SKIP] swiftlint / xcodegen / xcodebuild need macOS (CI ci job runs them)"
fi

echo ""
echo "Preflight: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
