#!/usr/bin/env bash
# Check that every commit since the last tag (or a given base) follows
# Conventional Commits and carries no AI agent attribution.
# Usage: bash scripts/check-conventional-commits.sh [base-ref]
# Based on danielvm-git/.github scripts/check-conventional-commits.sh, reading
# subjects with --format=%s (see specs/adr/0004-ci-cd-template-and-big-release.md).
set -euo pipefail

CONVENTIONAL_REGEX='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: '

default_base() {
  git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD
}

BASE="${1:-$(default_base)}"
RANGE="$BASE..HEAD"
# No tag yet: BASE is the root commit, which BASE..HEAD would skip. Check all history.
if [ "$BASE" = "$(git rev-list --max-parents=0 HEAD)" ]; then RANGE="HEAD"; fi
if [ "$(git rev-list --count "$RANGE")" -eq 0 ]; then
  echo "PASS: No commits since $BASE"
  exit 0
fi

echo "Checking commits: $RANGE"
FAILS=0

while IFS= read -r subject; do
  if ! echo "$subject" | grep -qE "$CONVENTIONAL_REGEX"; then
    echo "FAIL: Non-conventional commit: $subject"
    FAILS=$((FAILS + 1))
  fi
done < <(git log "$RANGE" --format=%s)

if git log "$RANGE" --format=%B | grep -qiE '^co[- ]authored[- ]by:'; then
  echo "FAIL: Co-authored-by: footer found — blocked by CONVENTIONS.md § Git Attribution"
  FAILS=$((FAILS + 1))
fi

if [ "$FAILS" -gt 0 ]; then
  echo "$FAILS violation(s) found"
  exit 1
fi
echo "PASS: All commits follow Conventional Commits, no AI agent attribution"
