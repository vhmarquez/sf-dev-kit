---
name: org-diff
description: Diff local Salesforce source vs. the target org and produce a structured drift report (setup-only changes, source-only changes, conflicts). Useful before deploys, after merge, or when investigating "why does the org behave differently from source?"
data-access: metadata-only
---

You are computing the drift between local source and the target org. Use `sf project retrieve preview` (which lists what *would* change without doing the retrieve) and present the results as a structured report.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/sf-cli.sh"
sf_cli_check || exit 2
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
```

## Input

`$ARGUMENTS`:
- (empty) — diff the entire project directory against the default org
- `<metadata-path>` — limit to one path (e.g., `force-app/main/default/classes`)
- `--target-org <alias>` — override default org
- `--env <name>` — load env override
- `--ci` — machine output (JSON or SARIF per `--format`)
- `--format json|sarif` — output format in CI mode (default `json`)
- `--out <path>` — write to file instead of stdout

## Steps

### 1. Verify state
- `sf_cli_alias_exists "$ORG"` — exit 2 if not
- Verify a `sfdx-project.json` exists in the working directory — exit 2 if not
- Verify the user has cleaned up obvious local-only churn (uncommitted noise can confuse the report). Print a short `git status -s` snapshot at the top of the report

### 2. Run preview retrieve
```bash
sf project retrieve preview --target-org "$ORG" --json > .sf-dev-kit-tmp/diff-preview.json
```
Capture both stdout and exit code. If it fails (auth, network), exit 2 with the underlying error.

The preview output has three buckets:
- `result.toRetrieve` — files in the org that are not in source (or differ — local would be overwritten)
- `result.toDelete` — files in source that are not in the org (would be deleted on retrieve)
- `result.conflicts` — files that differ on both sides since the last sync

### 3. Classify and structure

Build the report:

| Bucket | Meaning | Suggested action |
|--------|---------|------------------|
| **Setup-only** (`toRetrieve`) | Someone changed it in setup; source doesn't reflect it | Run `sf project retrieve start` to bring it into source |
| **Source-only** (`toDelete`) | New work in source not yet deployed | Run `sf project deploy start` to push |
| **Conflicts** (`conflicts`) | Both sides changed | Manual: inspect, decide which wins, merge |

### 4. Output

Default human-readable Markdown:

```
# Org Diff: <ORG>

Run at: 2026-04-28T10:35:00Z
Source: 75 changed metadata items vs. org

## Setup-only changes (5)

| Type | Member | Modified by | Modified at |
|------|--------|-------------|-------------|
| ApexClass | OrderHelper | jdoe@acme.com | 2026-04-27T14:02Z |
| ...

## Source-only changes (2)

| Type | Member | File |
|------|--------|------|
| ApexClass | NewController | force-app/.../NewController.cls |
| ...

## Conflicts (1)

| Type | Member | Source path | Org modified by | Org modified at |
|------|--------|-------------|-----------------|-----------------|
| LightningComponentBundle | acmeFoo | force-app/.../acmeFoo/ | jdoe@acme.com | 2026-04-27T13:50Z |

## Summary
- 5 items changed in setup that should be retrieved into source
- 2 items in source ready to deploy to the org
- 1 conflict requiring manual resolution
```

CI mode JSON shape (consumed by `/release-notes`, `/diff-deploy`, etc.):
```json
{
  "org": "DevVM",
  "ranAt": "2026-04-28T10:35:00Z",
  "setupOnly":  [{"type": "ApexClass", "member": "OrderHelper", "modifiedBy": "...", "modifiedAt": "..."}],
  "sourceOnly": [{"type": "ApexClass", "member": "NewController", "path": "..."}],
  "conflicts":  [{"type": "...", "member": "...", "path": "...", "orgModifiedBy": "...", "orgModifiedAt": "..."}]
}
```

CI mode SARIF: emit each conflict as a `warning`-level finding with `ruleId: "DRIFT-CONFLICT"`, each setup-only as `note`-level `ruleId: "DRIFT-SETUP-ONLY"`, each source-only as `note`-level `ruleId: "DRIFT-SOURCE-ONLY"`. Source via:
```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/sarif.sh"
```

### 5. Exit codes (per `${CLAUDE_PLUGIN_ROOT}/docs/ci-output-contract.md`)
- 0 — no drift (all three buckets empty)
- 1 — drift exists (any of the three has entries)
- 2 — the diff itself failed to run

## Rules

- **Don't auto-resolve conflicts.** This skill reports; it never retrieves or deploys
- **Surface the timestamp.** Org drift reports go stale fast; always include `ranAt`
- **Respect `.forceignore`.** Items excluded by `.forceignore` are not drift; the underlying `sf` command already honors it but verify in the output
- **Interactive sessions only.** If `--ci` is not set and there is no controlling terminal, don't paginate output — just print
