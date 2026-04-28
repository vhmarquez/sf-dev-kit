---
name: onboard
description: Onboard a new developer to a Salesforce project — verify Salesforce CLI version, Dev Hub authentication, project config, and run an end-to-end sanity check (scratch org create → deploy → tests pass). Outputs a checklist with green/red status per item.
---

You are walking a new developer through the prerequisites and a smoke test for this Salesforce project. The skill verifies their machine is set up correctly and that they can complete the basic dev loop end-to-end.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
DEV_HUB="$(sf_config_get '.platform.devHubAlias // \"DevHub\"' "$ENV")"
API_VERSION="$(sf_config_get '.platform.apiVersion' "$ENV")"
LINT_CMD="$(sf_config_get '.quality.lintCommand' "$ENV")"
TEST_CMD="$(sf_config_get '.quality.unitTestCommand' "$ENV")"
```

## Input

`$ARGUMENTS`:
- (empty) — full onboard check (verify + smoke)
- `verify` — checks only, no scratch org / deploy
- `smoke` — assumes verify passed; runs the smoke flow only
- `--ci` — JSON output, exit 1 if any check fails

## Steps

### 1. Tool versions

| Tool | Required | Check |
|------|----------|-------|
| `sf` (Salesforce CLI) | latest | `sf --version` |
| `node` | LTS (20+) | `node --version` |
| `npm` | bundled with node | `npm --version` |
| `git` | 2.30+ | `git --version` |
| `jq` | any 1.6+ | `jq --version` |
| `java` | 11+ (only if PMD-based skills will be used) | `java -version` 2>&1 |
| `bash` | 4+ (Git Bash on Windows) | `bash --version` |

For each, capture installed version and pass/fail.

### 2. Salesforce auth

```bash
# Dev Hub
sf_cli_alias_exists "$DEV_HUB" && echo "dev-hub: ✅" || echo "dev-hub: ❌ (run: sf org login web --alias $DEV_HUB --set-default-dev-hub)"
# Default target org
DEFAULT_ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
sf_cli_alias_exists "$DEFAULT_ORG" && echo "default-org: ✅" || echo "default-org: ❌ (run: sf org login web --alias $DEFAULT_ORG)"
```

### 3. Project state

| Check | How |
|-------|-----|
| `.claude/sf-project.json` exists | `[[ -f .claude/sf-project.json ]]` |
| Standards docs in place (`docs/apex-standards.md` etc.) | check the configured paths |
| Patterns docs in place | check `paths.patternsSalesforceDoc`, `paths.patternsProjectDoc` |
| `docs/project-context.md` has been filled in (no remaining `_TODO_` markers) | `! grep -q "_TODO_" docs/project-context.md` |
| `package.json` has `lint` and `test:unit` scripts | check `package.json` |

### 4. Repo state

| Check | How |
|-------|-----|
| Working tree clean | `git diff --quiet && git diff --cached --quiet` |
| Has at least one commit on a feature branch | `git log -1 --pretty=format:%H` |
| Remote configured | `git remote get-url origin` (warning if missing) |

### 5. Smoke flow (only in `smoke` or default mode)

Walk the user through:
1. Create a scratch org: `/sf-dev-kit:scratch-org create scratch-onboard --days 1 --no-seed`
2. Deploy is automatic (the scratch-org skill pushes source)
3. Run lint: invoke `${LINT_CMD}` from package.json
4. Run unit tests: invoke `${TEST_CMD}`
5. Run Apex coverage on a small class: `/sf-dev-kit:test-coverage <class> --target-org scratch-onboard`
6. Destroy the scratch org: `/sf-dev-kit:scratch-org destroy scratch-onboard`

For each step, report timing and pass/fail.

## Output

Default Markdown:
```
# Onboard: <project.name>

User: <git config user.email>
Run at: 2026-04-28T15:45:00Z

## Tools
- sf:    2.45.6      ✅
- node:  v20.11.1    ✅
- npm:   10.2.4      ✅
- git:   2.44.0      ✅
- jq:    1.7.1       ✅
- java:  17.0.10     ✅
- bash:  5.2.21      ✅

## Auth
- Dev Hub (DevHub):           ✅
- Default org (DevSandbox):   ✅

## Project state
- .claude/sf-project.json:                  ✅
- docs/apex-standards.md:                   ✅
- docs/lwc-standards.md:                    ✅
- docs/quality-checklist.md:                ✅
- docs/patterns/salesforce-patterns.md:     ✅
- docs/patterns/project-patterns.md:        ✅
- docs/project-context.md filled in:        ⚠️  (still has 3 `_TODO_` markers)
- package.json scripts (lint + test:unit):  ✅

## Repo state
- Working tree clean:    ✅
- Has commits:           ✅
- Remote configured:     ✅ (origin: github.com/...)

## Smoke flow
- Scratch org create:    ✅ (8.2s)
- Source push:           ✅ (54.1s, 137 components)
- Lint:                  ✅ (1.3s)
- Unit tests (Jest):     ✅ (12 tests, 0 failures, 4.7s)
- Apex coverage on Order:    ✅ (94.7%, target 85%)
- Scratch org destroy:   ✅ (1.1s)

## Result
**Ready to develop.** ✅

## Recommended next reads
- README.md (project overview)
- docs/project-context.md (object model + glossary)
- docs/patterns/project-patterns.md (project-specific patterns)
- The pattern docs SF-1..SF-20 in docs/patterns/salesforce-patterns.md

## Suggested next command
`@architect: design a small change` — to see the full architect → dev → qa flow in action.
```

CI mode: emit JSON object with `{ tools: {...}, auth: {...}, project: {...}, repo: {...}, smoke: {...}, ok: bool }`. Exit 1 if any item failed.

### 6. Exit codes
- 0 — all checks passed
- 1 — any check failed (in `--ci`)
- 2 — invocation error

## Rules

- **Don't skip on warnings.** If `docs/project-context.md` has `_TODO_` markers, that's a real onboarding gap; flag as warning
- **Don't run smoke if verify fails.** Bail out cleanly with a summary
- **Clean up after yourself.** Always destroy the scratch org created during smoke, even on partial failure
- **Honor `--days 1`** for the smoke scratch — short-lived; don't hold a slot longer than needed
- **Don't commit anything.** This skill is read-only against the repo

## Consumers

- New developer joining the project
- CI bootstrap step (verify-only mode) confirming the runner has prerequisites
- Periodic check — `/sf-dev-kit:onboard verify --ci` in a weekly job to detect drift
