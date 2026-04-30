---
name: coverage-trend
description: Persist Apex code-coverage results over time and surface regressions. After each /argo:test-coverage run (or via this skill directly), append the result to a per-project history file and show the trend. PR-mode diffs against the baseline.
data-access: metadata-only
---

You are tracking Apex coverage over time so regressions are visible. The history is per-project, stored in `${CLAUDE_PLUGIN_DATA}/argo/coverage/<project>/history.jsonl` (one JSON line per run).

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
PROJECT_NAME="$(sf_config_get '.project.name' "$ENV")"
COVERAGE_TARGET="$(sf_config_get '.quality.codeCoverageTarget' "$ENV")"
SLUG="$(printf '%s' "$PROJECT_NAME" | tr '[:upper:] /' '[:lower:]_-' | tr -cd 'a-z0-9_-')"
HISTORY_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugin-data}/argo/coverage/${SLUG}"
mkdir -p "$HISTORY_DIR"
```

## Input

`$ARGUMENTS`:
- (empty) — run `sf apex run test --code-coverage` and append the result to history
- `record <coverage-json>` — accept a coverage JSON from another tool (e.g., the existing `/test-coverage` skill); append it to history
- `show [--last N]` — print the last N runs (default 10) as a Markdown table
- `diff [--vs <ref>]` — compare current coverage against the run at git ref `<ref>` (default `main` HEAD)
- `pr` — PR mode: compute diff vs. `main`, exit 1 if any class regressed, exit 0 if same or improved
- `--target-org <alias>` / `--env <name>` — for the `sf` query in default mode

## Steps

### 1. Run coverage (default mode) or accept input (record mode)

Default:
```bash
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
sf apex run test --target-org "$ORG" --test-level RunLocalTests --code-coverage --result-format json --wait 30 > /tmp/cov.json
```

Capture per-class coverage from the JSON. Compute project-wide rollup.

### 2. Build the history record

```json
{
  "ranAt":     "2026-04-28T12:30:00Z",
  "git":       { "branch": "main", "sha": "abc123", "isDirty": false },
  "overall":   { "coveredLines": 12450, "totalLines": 14200, "percent": 87.7 },
  "perClass":  [
    { "name": "OrderService", "covered": 142, "total": 150, "percent": 94.7 },
    { "name": "OrderApiClient", "covered": 38, "total": 60, "percent": 63.3 }
  ],
  "target":    85,
  "passed":    true
}
```

Append to `${HISTORY_DIR}/history.jsonl` as a single line.

### 3. `show [--last N]`

Read the last N records. Output a Markdown table:

```
# Coverage Trend: <project.name>

| Run                  | Overall | Δ      | Below Target |
|----------------------|---------|--------|--------------|
| 2026-04-28T12:30:00Z | 87.7%   | +0.2%  | OrderApiClient (63.3%) |
| 2026-04-27T18:14:22Z | 87.5%   | -0.5%  | OrderApiClient (63.3%) |
| ...
```

### 4. `diff [--vs <ref>]`

Find the most recent history record whose `git.sha` matches `<ref>`'s HEAD. Compare class-by-class against the latest record. Output:

```
# Coverage Diff: HEAD vs main (abc123)

## Improved
- OrderService:    91.2% → 94.7% (+3.5%)

## Regressed
- OrderApiClient:  72.0% → 63.3% (-8.7%) ⚠️

## New classes (no baseline)
- DiscountEngine:  85.0%

## Removed classes (baseline only)
- (none)

## Overall: 87.5% → 87.7% (+0.2%)
```

### 5. `pr` mode

Run `diff` internally. Exit 1 if any class regressed by more than a configurable epsilon (default 0.5 percentage points), exit 0 otherwise. Print the diff regardless.

CI integration: emit findings (one per regression) following the standard contract:
- `ruleId: "COV-REGRESSION"` (warning) — class regressed but still ≥ target
- `ruleId: "COV-BELOW-TARGET"` (error) — class below `quality.codeCoverageTarget`%

### 6. Exit codes
- 0 — clean, or `show`/`diff` informational
- 1 — `pr` and any regression > epsilon, or any class below target
- 2 — query/setup error

## Rules

- **Per-line aggregation, not per-method.** Salesforce reports lines covered/total; that's the source of truth
- **Only persist on success.** If `sf apex run test` fails, don't append a noise record
- **Don't track tests; track production classes.** Skip anything ending in `naming.apex.testSuffix`
- **History is append-only.** Never rewrite past lines — even if a class is renamed; the rename is its own diff event
- **Truncate display.** `show` defaults to last 10 runs to keep the table readable

## Consumers

- CI pipelines run `coverage-trend pr` to gate merges on coverage regression
- `/argo:release-notes` pulls the latest record to include "Coverage: X%" in release notes
- `@qa` consults the history when a class drops below target to recommend which tests to add
