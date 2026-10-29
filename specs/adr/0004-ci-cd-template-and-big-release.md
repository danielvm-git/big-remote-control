# ADR 0004 — CI/CD from the .github template, releases by big-release

- Status: accepted
- Date: 2026-10-29

## Context

The owner's fleet standard is `danielvm-git/.github` (`workflow-templates/ci-cd-swift.yml`
v2.0.0) and `danielvm-git/big-release` for versioning.

## Decision

- `.github/workflows/ci-cd.yml` keeps the template's `ci` + `verify` jobs and adds the
  `release` job pattern from big-release's own `release.yml`.
- `ci` runs on macOS with the Xcode app-target variant (XcodeGen + xcodebuild) and Preflight.
- `verify` checks Conventional Commits and blocks `Co-authored-by` since the last tag.
  Deviation: it reads `--format=%s`, not `--oneline` (the template's `--oneline` puts the
  SHA first, so `^(feat|...)` never matches on a pull request).
- `release` installs the published big-release binary (pinned version + SHA-256) and runs it
  with `changelog`, `git`, `github` plugins. No package publisher: this is an app, not an SPM package.

## Consequences

- big-release is pinned to 2.5.1, which accepts `branches: - main`
  (danielvm-git/big-release#73, found here on 2.5.0).
- The template's `--oneline` check was fixed upstream in danielvm-git/.github#39 (templates 4.2.1).
- Version authority is the git tag; `CHANGELOG.md` is committed by big-release (`[skip ci]`).
- No `.app` asset is attached yet (unsigned, owner-only). Revisit with notarization.
