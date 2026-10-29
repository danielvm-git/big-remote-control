# Conventions

Base: bigpowers `CONVENTIONS.md` (v2.88) + `profiles/swift.md` + `profiles/solo-git.md`.
CI/CD follows the `danielvm-git/.github` `ci-cd-swift.yml` template and `big-release`.

## Conventional Commits & Semantic Versioning

All changes MUST follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).
Versioning MUST follow [Semantic Versioning 2.0.0](https://semver.org/).

### Commit Message Format

`<type>(<scope>): <description>` (Space after colon is MANDATORY). Subject ≤ 72 characters.

### Types & Version Bumps

- `feat`: Minor (x.Y.z) - New feature
- `fix`: Patch (x.y.Z) - Bug fix
- `perf`: Patch (x.y.Z) - Performance improvement
- `docs`, `chore`, `style`, `refactor`, `test`, `build`, `ci`: No bump (unless breaking)
- `BREAKING CHANGE:` (or `!` after type): Major (X.y.z)

### The version is never hand-tracked

`big-release` decides the version on every push to `main` from the commits since the last tag.
The authority is the git tag `vX.Y.Z` and `gh release view`. `CHANGELOG.md` is generated.
`CFBundleShortVersionString` in `project.yml` is a display label, not the authority.

## GitHub & Git Operations

- No direct work on `main`. Every task MUST start on a feature branch or worktree (`kickoff-branch`).
- **Integrate (solo profile):** ship with `bash scripts/land-branch.sh <branch> "<conventional message>"` after Preflight is green. PR is optional.
- `git push origin <feature-branch>` is allowed for backup or CI. Never push to `main` except via `land-branch.sh`.
- Use `gh repo clone` not `git clone` for GitHub repos.
- Use `gh run view` / `gh run watch` for CI status.
- Verify auth with `gh auth status` before operations.
- **Git Attribution:** NEVER include `Co-authored-by` or any footer that attributes code to an AI agent. CI blocks it.
- Never call the GitHub REST API directly (curl, fetch). Use `gh`.
- Never create GitHub issues from automated workflows — write `specs/bugs/BUG-*.md` instead.

## Agent Workflow Mandates

- **No Direct Coding:** Route feature work through bigpowers skills. Start with `survey-context` when context is missing.
- Use `plan-work` before feature code. Use `develop-tdd` or `execute-plan` to implement.
- Use `investigate-bug` for bug reports before writing a fix.
- **Verification Mandate:** Every story ends with a step-by-step manual check on a real TV. Wait for the user to confirm.
- **Traceability Mandate:** Every story MUST have ≥1 `story: eNNsNN` tag in its implementing code or test file.
- **TV safety:** Ask the user before any command that changes TV state. Read-only REST `GET` needs no approval.

## Always Green / Shift Left

**Always Green** means Preflight and CI are green before any forward work — not "green enough for this task."

**Shift Left (1-10-100):** Defects cost roughly 1× in development, 10× in integration, 100× in production.

**Preflight** — `bash scripts/preflight.sh`: SwiftLint (strict), XcodeGen, build and tests. It MUST pass before kickoff, develop or verify.

**CI green** — the `CI/CD` workflow MUST pass before a land counts as done.

## Discovered Defects

Any **reproducible gate failure** found during unrelated work is a discovered defect.

**fix-or-log ladder (mandatory):**

1. **quick-fix** — trivial, data-only, or single-file fixes within guardrails.
2. **fix-bug** — when quick-fix aborts, or the failure needs investigation (`specs/bugs/BUG-*.md` + TDD).
3. **Log** — only when reproduction is blocked after a good-faith attempt; write a BUG spec and stop.

Discovered fixes ship with the original work but in **separate commits**. Never narrate a failure and continue.

### Banned dismissive phrases

| Banned phrase | Required behavior instead |
|---------------|---------------------------|
| Pre-existing / pre-existing issues | Run fix-or-log; if truly unrelated, prove with a passing repro after revert |
| unrelated to this session | Same — session boundaries do not waive green gates |
| not introduced by my changes | Bisect or fix anyway; solo-default owns the whole tree |
| out of scope (ignoring a red gate) | Invoke quick-fix or fix-bug; scope-minimization never overrides Always Green |

## specs/ — All Planning Output Goes Here

| Question | File |
|----------|------|
| What should the product do? | `specs/product/SCOPE_LATEST.yaml` |
| North star | `specs/product/VISION_LATEST.yaml` |
| Glossary | `specs/product/GLOSSARY_LATEST.yaml` |
| What ships next, in what order? | `specs/release-plan.yaml` |
| Story status (sole source of truth) | `specs/execution-status.yaml` |
| Where are we in the session? | `specs/state.yaml` (`workflow_mode: solo-git`) |
| Stack / architecture | `specs/tech-architecture/tech-stack.md` |
| Irreversible decisions | `specs/adr/NNNN-*.md` |
| Live-device verification | `specs/verifications/` |
| Bugs | `specs/bugs/BUG-*.md` + `specs/bugs/registry.yaml` |

Do not put story status in `release-plan.yaml`.

## Code Style

- Functions: 4–20 lines. Split if longer.
- Files: under 300 lines. Split by responsibility (e.g. `AppModel+Power.swift`).
- One responsibility per type and per file (SRP).
- Names: specific and unique. Prefer names whose grep returns < 5 hits.
- Early returns over nested ifs. Max 2 levels of indentation.
- Names describe side-effects: `sendPowerKeyIfStandby`, not `handlePower`.
- No magic strings or numbers in logic: extract a named constant or a `Protocol/` payload builder.
- Complex boolean logic goes in a named predicate.
- Prefer thrown errors over sentinel values. `TVError` messages MUST tell the user how to recover.
- Remove dead code. Do not comment it out.
- Boy Scout Rule: leave every touched file at least as clean as you found it.

## Stack Conventions (Swift)

- Prefer MVVM: View → `AppModel` → Service actors.
- Use `struct` for value types; `class` only for reference semantics; `actor` for shared mutable I/O state.
- Async: `async/await` and task groups. No callback pyramids.
- Naming: Swift API Design Guidelines.
- Never force-unwrap (`!`) in production paths without a documented invariant.
- Never commit `DerivedData/`, `build/` or the generated `BigRemote.xcodeproj/`.
- SwiftLint exceptions live in `.swiftlint.yml`, each with a WHY comment.

## Comments

- Write WHY, not WHAT.
- A line that exists because of a live TV finding MUST cite it (`docs/PROTOCOL.md` or an ADR).
- Docstrings on non-obvious public functions: intent first.
- No commented-out code.

## Tests (F.I.R.S.T)

- Tests run headless with one command (AGENTS.md § Test). They never touch the network or a TV.
- Every new function in `Models/` or `Services/Protocol/` gets a test. Every bug fix gets a regression test.
- Test boundary values: empty input, maximum, minimum, off-by-one.
- Test through public interfaces only.
- Never skip a test without an ambiguity note.

## Dependencies

- No third-party runtime dependencies. Foundation, Network, SwiftUI only.
- Inject dependencies through initializers (e.g. `ChannelSocket(session:)`).

## Formatting

- SwiftLint (`.swiftlint.yml`) is the formatter gate. No style debates beyond it.

## Logging

- User-facing feedback goes through `AppModel.show(_:)` in pt-BR.
- No secrets (TV tokens, SmartThings token) in logs or banners.

## Defensive Code

- **Retry with backoff** — art channel: back off 30 s → 4 min after 3 unanswered requests.
- **Timeout** — every socket handshake and REST call has a hard deadline.
- **Graceful degradation** — SmartThings is optional; a missing token never blocks LAN features.

The agent implements defensive code only for the categories listed here.

## File-Size Exceptions

No exceptions today. Any new exception needs a row here with rationale and a review date.

| File | Lines | Rationale | Review date |
|------|-------|-----------|-------------|
