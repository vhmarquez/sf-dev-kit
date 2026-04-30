---
name: release-notes
description: Generate release notes from git commits + tags + ADRs + coverage history since the last release. Output is Markdown grouped by category (Features, Fixes, Refactors, Docs, etc.), with deploy/coverage stats and links to the relevant ADRs.
data-access: none
---

You are producing **release notes** for a Salesforce project. The notes are derived from git history, ADRs added since the last release, and the latest coverage record.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
PROJECT_NAME="$(sf_config_get '.project.name' "$ENV")"
```

## Input

`$ARGUMENTS`:
- (empty) — generate notes from the last tag to HEAD
- `--from <ref>` — start ref (default: latest semver tag like `v1.x.y`)
- `--to <ref>` — end ref (default: HEAD)
- `--out <path>` — file path (default: `docs/releases/<version>.md`)
- `--version <vX.Y.Z>` — release version (default: bump from latest tag)
- `--ci` — machine JSON

## Steps

### 1. Resolve refs and version

```bash
LATEST_TAG=$("$GIT" describe --tags --abbrev=0 --match='v*' 2>/dev/null || echo "")
FROM="${FROM:-${LATEST_TAG:-$(git rev-list --max-parents=0 HEAD)}}"
TO="${TO:-HEAD}"
VERSION="${VERSION:-$(echo "$LATEST_TAG" | awk -F. '{$NF++; print}' OFS=.)}"
[[ -z "$VERSION" ]] && VERSION="v1.0.0"
```

### 2. Walk commits

```bash
"$GIT" log --pretty='format:%H%x09%s%x09%an%x09%aI' "$FROM..$TO" > /tmp/release-commits.tsv
```

Parse each line. Classify by Conventional Commit prefix:

| Prefix | Section |
|--------|---------|
| `feat` | Features |
| `fix` | Fixes |
| `perf` | Performance |
| `refactor` | Refactors |
| `docs` | Documentation |
| `test` | Tests |
| `chore`, `build`, `ci` | Internal |
| (none) | Other |

Skip merge commits and `Merge phase/...` lines (those are integration noise; the underlying commits are already in the log).

### 3. Pull ADRs added in range

```bash
"$GIT" log --diff-filter=A --name-only --pretty=format: "$FROM..$TO" -- 'docs/adr/[0-9]*.md' | grep -v '^$' | sort -u
```

For each new ADR, parse its front-matter for title and status. Surface in a "Decisions" section.

### 4. Pull latest coverage

```bash
HISTORY="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugin-data}/argo/coverage/<slug>/history.jsonl"
[[ -f "$HISTORY" ]] && jq -s 'last' "$HISTORY"
```

Include `overall.percent` and any `perClass.*` below `quality.codeCoverageTarget` in a "Quality" section.

### 5. Pull deploys in range (optional)

```bash
DEPLOYS="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugin-data}/argo/deploys/<slug>/history.jsonl"
[[ -f "$DEPLOYS" ]] && jq -s --arg from "$(git show -s --format=%cI "$FROM")" 'map(select(.deployedAt > $from))' "$DEPLOYS"
```

Surface count of deploys / quick-deploys in the range.

### 6. Output

Default Markdown:
```
# <project.name> v1.4.0

Released: 2026-04-28
Range: v1.3.0 → HEAD (47 commits, 6 contributors)

## Highlights
- (top 3 features by commit subject — synthesize)

## Features
- `feat(architect)`: add automation-type rec, risk/blast-radius, effort, test strategy (`d3f650f`)
- `feat(skills)`: add org-awareness skills (`50d2693`)
- ...

## Fixes
- `fix(lint-lwc)`: surface Prettier and ESLint failures (`db0a26f`)

## Performance
- (none)

## Refactors
- (none)

## Documentation
- `docs`: define CI output contract (`fde4a1f`)

## Decisions
- ADR-0007: [Use Custom Metadata for feature flags](docs/adr/0007-use-custom-metadata-for-feature-flags.md) — Accepted

## Quality
- Apex coverage: 87.7% (target 85%) ✅
- Below-target classes: OrderApiClient (63.3%) — see ADR-0009 for context

## Operations
- 4 deploys to dev, 2 quick-deploys to prod in this range

## Internal (not user-facing)
- `chore`: bump plugin to 1.4.0
- `build`: enforce LF line endings
- ...
```

CI mode: emit JSON with the same data structured.

### 7. Optional: write a CHANGELOG.md update

If `--update-changelog` is passed, prepend the generated content to `CHANGELOG.md` (or create it).

## Exit codes
- 0 — notes generated
- 2 — git ref not found / config error

## Rules

- **One source of truth: commit subjects.** Don't paraphrase; quote the subject. Conventional prefix → category mapping is authoritative
- **Surface ADRs separately.** They're decision records, not features
- **Don't include AI co-author footers.** They're noise in user-facing release notes. Strip lines matching `^Co-Authored-By:` from rendered subjects
- **Group internal under "Internal".** Most readers skip it; it's there for completeness

## Consumers

- Release pipeline: generate → publish to GitHub Releases
- Slack/Teams notifier (Phase 9): paste the Highlights section into the channel post
