---
name: diff-deploy
description: Deploy only the metadata that's changed since a git ref (default `main`) instead of the full project. Reads `git diff` to compute the changed-file set, intersects with the project's `paths`, and runs `sf project deploy start` with --source-dir flags. Useful for fast PR validation deploys.
data-access: metadata-only
---

You are deploying **only the metadata that has changed** between the current state and a git reference. Full-project deploys can take 5–30 minutes; diff deploys typically take seconds-to-minutes.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
TEST_SUFFIX="$(sf_config_get '.naming.apex.testSuffix' "$ENV")"
```

## Input

`$ARGUMENTS`:
- (empty) — diff against `main` HEAD; deploy the changed metadata
- `--vs <ref>` — diff against a specific git ref (`main`, `origin/main`, a tag, a commit SHA)
- `--validate` — run as `--dry-run` (validate only, no actual deploy)
- `--target-org <alias>` / `--env <name>` — standard overrides
- `--include-tests` — include test classes in the deploy (default: include only when their production class also changed)
- `--ci` — machine output (deploy id, status, errors) as JSON

## Steps

### 1. Resolve the diff base

```bash
BASE="${VS:-main}"
"$GIT" rev-parse "$BASE" >/dev/null 2>&1 || { echo "[diff-deploy] base ref not found: $BASE" >&2; exit 2; }
```

### 2. Compute the changed-file set

```bash
"$GIT" diff --name-only --diff-filter=AMR "$BASE"...HEAD > /tmp/diff-deploy-files.txt
```

Filter to:
- Only files under `force-app/` (or whatever `packageDirectories` are in `sfdx-project.json`)
- Exclude `.forceignore`-matched files (use `sf project list ignored` if available, otherwise read `.forceignore` directly)

### 3. Resolve metadata bundles

LWC and Aura components live in directories — a single file change must deploy the **whole bundle**:
- For any file under `<lwcSource>/<component>/`, deploy the entire `<component>/` directory
- For any file under `<aura>/<component>/`, deploy the entire `<aura>/<component>/` directory
- For Apex classes/triggers, deploy the `.cls` + `.cls-meta.xml` pair (or `.trigger` + `.trigger-meta.xml`)
- For object/field changes, deploy the relevant `objects/<Object>/` subtree (or just `<Object>/fields/<Field>.field-meta.xml`)
- For permission sets, profiles: deploy the file as-is

Build a deduplicated list of `--source-dir` paths.

### 4. Include relevant test classes

For each modified Apex class `Foo.cls`:
- If `Foo<TestSuffix>.cls` exists in source, include it
- The test runs server-side as part of the deploy (RunSpecifiedTests or RunLocalTests)

### 5. Build the deploy command

```bash
sf project deploy start \
  --target-org "$ORG" \
  $([ "$VALIDATE" = "1" ] && echo "--dry-run") \
  $(printf -- "--source-dir %q " "${PATHS[@]}") \
  --test-level RunSpecifiedTests \
  $(printf -- "--tests %q " "${TEST_CLASSES[@]}") \
  --wait 30 \
  --json > /tmp/diff-deploy-result.json
```

Capture exit code + JSON output.

### 6. Output

Default Markdown:
```
# Diff Deploy: <ORG>

Diff base: main (abc123)
Changed metadata: 7 components, 12 files
Tests run: 4 classes, 23 methods

## Components deployed
- LightningComponentBundle: acmeOrderForm
- ApexClass: OrderController, OrderService
- CustomObject (field-only changes): Order__c.Status__c

## Test results
✅ 23 passed / 0 failed / 0 skipped

## Status
✅ Deploy succeeded (12.4s)
Deploy ID: 0Af...XYZ
```

CI mode JSON shape:
```json
{
  "org": "DevVM",
  "diffBase": "main",
  "deployId": "0Af...XYZ",
  "status": "Succeeded",
  "validateOnly": false,
  "components": [{"type": "ApexClass", "fullName": "OrderController"}],
  "testsRun": 23,
  "testFailures": 0,
  "errors": []
}
```

### 7. Exit codes
- 0 — deploy succeeded (or validate succeeded)
- 1 — deploy failed (validation failure or test failure)
- 2 — invocation error (no diff, base ref invalid, etc.)

## Rules

- **Always include the meta files.** A `.cls` deploys with its `.cls-meta.xml`; the diff-file computation must add the meta when the source is touched and vice versa
- **LWC/Aura bundles deploy whole.** Even if only the CSS changed, the meta file must be in the deploy or the package is invalid
- **Renames are tricky.** `--diff-filter=AMR` includes Renames; the renamed source path is what we deploy. Salesforce sees this as "delete old, add new" — confirm `.forceignore` doesn't accidentally exclude the new name
- **Include test classes for changed production classes.** `--include-tests` to also include all test classes in the diff (rare; mostly when refactoring tests themselves)
- **Persist the deploy ID.** Append the result to `${CLAUDE_PLUGIN_DATA}/sf-dev-kit/deploys/<project>/history.jsonl` so `/quick-deploy` can find it later
- **Don't auto-deploy to prod.** If the alias matches `prod*` or `*production*`, require `--validate` first or an explicit confirmation prompt

## Consumers

- CI pipelines run `--validate` on PRs
- `/sf-dev-kit:quick-deploy` reads the persisted deploy ID
- `/sf-dev-kit:release-notes` lists components since the last successful prod deploy
