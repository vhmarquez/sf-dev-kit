---
name: quick-deploy
description: Promote a previously validated deployment to production without re-running tests. Salesforce honors a quick-deploy of any validated deploy ID within 4 days, skipping the test phase. Saves 20–60 minutes on prod releases.
---

You are running a **quick-deploy** — taking a deploy ID that's already passed validation and promoting it to actually apply. Salesforce's quick-deploy is the only sanctioned way to skip tests on a production deploy.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
HISTORY="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugin-data}/sf-dev-kit/deploys/${PROJECT_SLUG}/history.jsonl"
```

## Input

`$ARGUMENTS`:
- (empty) — show available validated deploy IDs from history; prompt for one
- `<deployId>` — quick-deploy the specified ID
- `--validate-first` — run `/sf-dev-kit:diff-deploy --validate` first, then quick-deploy the resulting ID
- `--target-org <alias>` / `--env <name>` — standard overrides
- `--ci` — machine output

## Steps

### 1. Resolve a deploy ID

If `<deployId>` was provided, validate its format (`0Af` prefix, 18 chars).

If empty, read the history file and surface validated deploys within the last 4 days:
```bash
jq -r 'select(.status == "ValidatedSucceeded" and (.validatedAt | fromdate) > (now - 345600)) | "\(.deployId)  \(.validatedAt)  \(.summary)"' "$HISTORY"
```
Prompt the user to pick one.

If `--validate-first`, dispatch to `/sf-dev-kit:diff-deploy --validate` and capture the deploy ID from its output.

### 2. Verify the deploy ID is still valid for quick-deploy

```bash
sf org login   # already logged in; this is just a sanity check
sf data query --target-org "$ORG" --use-tooling-api --json --query "
  SELECT Id, Status, NumberComponentsDeployed, NumberComponentErrors, NumberTestsCompleted,
         CompletedDate, CreatedDate, CheckOnly
  FROM DeployRequest
  WHERE Id = '<deployId>'
"
```

Validate:
- `Status = 'Succeeded'`
- `CheckOnly = true` (it was a validation, not a real deploy)
- `CompletedDate` within the last 96 hours
- `NumberTestsCompleted > 0`
- `NumberComponentErrors = 0`

If any check fails, refuse and explain why.

### 3. Run quick-deploy

```bash
sf project deploy quick \
  --target-org "$ORG" \
  --job-id "<deployId>" \
  --wait 30 \
  --json > /tmp/quick-deploy-result.json
```

### 4. Output

Default Markdown:
```
# Quick Deploy: <ORG>

Validated deploy ID: 0Af...XYZ
Validated at: 2026-04-26T14:22:00Z (49h ago)
Components: 7
Tests: 23 (all passed at validation)

## Status
✅ Quick-deploy succeeded (4.1s — no test re-run)
Deploy ID: 0Af...ABC (the actual deploy; validate ID was 0Af...XYZ)

## What happened
- Salesforce reused the test results from validation
- Components were applied to the org
- Total time: 4 seconds (vs ~22 minutes for a fresh deploy with tests)
```

CI mode JSON: `{"validateId": "0Af...XYZ", "deployId": "0Af...ABC", "status": "Succeeded", "elapsedMs": 4123}`.

### 5. Append to history

```bash
echo '{"deployId":"0Af...ABC","validateId":"0Af...XYZ","status":"Succeeded","quickDeployedAt":"...","org":"...","componentCount":7}' >> "$HISTORY"
```

### 6. Exit codes
- 0 — quick-deploy succeeded
- 1 — quick-deploy failed (rare — validation guarantees the metadata is valid; failure here means something else changed in the org)
- 2 — invocation error (deploy ID invalid, expired, not a CheckOnly, etc.)

## Rules

- **Only deploy validated `CheckOnly = true` deploys.** A real deploy ID won't quick-deploy
- **Honor the 96-hour window.** Salesforce returns an error past that anyway — fail fast with a clear message
- **Confirm the deploy was clean.** `NumberComponentErrors = 0` AND tests passed. A failed validation can't be quick-deployed
- **History is append-only.** Never rewrite past records; both validation and quick-deploy events become rows
- **Don't quick-deploy across orgs.** A deploy ID is org-specific; don't try to use a sandbox validation ID against prod

## Consumers

- Release process: developer runs `/diff-deploy --validate` against prod → notes the deploy ID → runs `/quick-deploy <id>` after change-window approval. Saves the ~20-min test run
- CI: validate on PR, persist; release pipeline picks up the ID and quick-deploys
