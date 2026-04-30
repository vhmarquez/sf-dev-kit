---
name: deploy
description: Deploy or validate Salesforce metadata against the project's default org (or another org if specified). Routes through the @salesforce/mcp `metadata` toolset when available; falls back to direct `sf` CLI. Honors per-environment config overrides via `--env`.
data-access: metadata-only
---

You are deploying Salesforce metadata for this project. Always read the project config first.

## Read Project Config

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/sf-cli.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/mcp.sh"
sf_cli_check || exit 2
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
LWC_SRC="$(sf_config_get '.paths.lwcSource' "$ENV")"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
REACT_SRC="$(sf_config_get '.paths.reactSource // ""' "$ENV")"
TEST_SUFFIX="$(sf_config_get '.naming.apex.testSuffix // "Test"' "$ENV")"
```

`--env <name>` merges `.claude/sf-project.<name>.json` over the base; if a prod override caps `mcp.toolsets` to read-only, this skill detects that and refuses to deploy through MCP — falling back to the user-authenticated CLI path.

## Input

The user provided: `$ARGUMENTS`

Targets:
- An LWC component name — deploy the component bundle and any Apex dependencies
- An Apex class name — deploy the Apex class plus its test class (if one exists)
- A React component name — deploy the React bundle (when react is in scope)
- A file path — deploy that specific path
- The word `all` — deploy the full project
- (empty) — prompt the user to specify what to deploy

Modifiers:
- `validate` or `--validate` — run validation only (`--dry-run`); no actual deploy
- `--target-org <alias>` — override `platform.defaultTargetOrg`
- `--env <name>` — read the env override; in particular pulls `defaultTargetOrg` from the env file
- `--ci` — non-interactive; machine-readable output; no prompts
- `--format json|sarif` — output format in CI mode (default `json`)
- `--out <path>` — write CI output to file instead of stdout
- `--mcp` / `--no-mcp` — force MCP-routed or CLI-routed deploy (default: prefer MCP when available)
- `--tests` `RunSpecifiedTests|RunLocalTests|RunAllTestsInOrg|NoTestRun` — test level on the deploy (default: `RunSpecifiedTests` for class-targeted deploys, `NoTestRun` for component-only deploys, `RunLocalTests` for `all`)

## Steps

### 1. Parse the input

Determine target kind, validation-only or real deploy, target org alias.

### 2. Resolve source paths

- LWC name: `${LWC_SRC}/<component>/`
  - Find Apex dependencies by grepping the JS for `@salesforce/apex/<Class>.<method>` imports; include each `<Class>.cls` + meta + test class
- Apex name: `${APEX_SRC}/<ClassName>.cls` + `<ClassName>.cls-meta.xml`
  - Include the test class `${APEX_SRC}/<ClassName><TEST_SUFFIX>.cls` + meta if it exists
- React name: `${REACT_SRC}/<ComponentName>/` (refuse with rule `DEPLOY-NO-REACT` if `platform.frontend = "lwc"`)
  - Find Apex dependencies the same way as LWC (grep the React source for `@salesforce/apex/` and `@salesforce/react/apex/` imports)
- File path: deploy that path verbatim
- `all`: full `force-app` directory

Verify all resolved paths exist before deploying. Refuse with rule `DEPLOY-PATH-MISSING` (severity: error) if any do not.

### 3. Pick the transport

```bash
if [[ "${MCP_OVERRIDE:-}" == "off" ]]; then
  ROUTE=cli
elif mcp_prefer && mcp_configured_toolsets "$ENV" | grep -qw metadata; then
  ROUTE=mcp
else
  ROUTE=cli
fi
```

The `metadata` MCP toolset must be in `mcp.toolsets` for the env. Read-only env overrides (e.g., a `prod` profile that ships `data,testing` only) will deliberately not include `metadata`; the skill falls back to CLI in that case.

### 4. Build and run the deploy

CLI route:
```bash
sf project deploy start \
  --target-org "$ORG" \
  --source-dir "$P1" --source-dir "$P2" \
  ${VALIDATE:+--dry-run} \
  --test-level "$TEST_LEVEL" \
  --wait 30 --json
```

MCP route:
```bash
mcp_run metadata deploy '{
  "org":         "'"$ORG"'",
  "sourceDirs":  ["'"$P1"'", "'"$P2"'"],
  "validateOnly": '"$VALIDATE_BOOL"',
  "testLevel":   "'"$TEST_LEVEL"'"
}'
```

Both paths return JSON. Capture deploy id, status, error/test failure arrays.

### 5. Production confirmation

Before deploying (not validating) to an org whose alias matches `prod*` / `production*` or whose username domain looks production-shaped, **prompt** for confirmation in interactive mode. In `--ci` mode, refuse and exit with rule `DEPLOY-PROD-REQUIRES-EXPLICIT` (severity: error) unless `--target-org` was set explicitly to that alias on the command line.

### 6. Append to deploy history

```
${CLAUDE_PLUGIN_DATA}/argo/deploy-history/<project>.jsonl
```

One JSON line per deploy: `{ deployId, org, env, mode (deploy|validate), route (mcp|cli), targetCount, status, durationSec, timestamp }`. `/argo:quick-deploy` reads this to find a recent successful validation.

### 7. Output

Default Markdown:
```
# Deploy: <project> → <org>

Mode:    deploy (or validate)
Route:   mcp / cli
Targets: 3 paths, 12 components

## Result
✅ Succeeded — Deploy Id 0Af...
   • 12 components deployed
   • 4 test methods run, 4 passed, 0 failed
   • Duration: 47s

## Components
- ApexClass:OrderController
- ApexClass:OrderControllerTest
- LightningComponentBundle:acmeOrderList
- ...
```

CI mode JSON:
```json
{
  "deployId": "0Af...",
  "org": "DevVM",
  "mode": "deploy",
  "route": "mcp",
  "status": "Succeeded",
  "componentCount": 12,
  "testRunCount": 4,
  "testFailureCount": 0,
  "durationSec": 47,
  "findings": []
}
```

CI mode SARIF: surfaces deploy errors and test failures as findings (`ruleId: DEPLOY-COMPONENT-ERROR`, `DEPLOY-TEST-FAILURE`).

### 8. Exit codes

- 0 — deploy / validate succeeded; no findings at or above `--fail-on`
- 1 — deploy / validate failed, OR findings at or above `--fail-on`
- 2 — invocation error (config missing, target not found, refusal in CI mode)

## Rules

- **Default to `platform.defaultTargetOrg` from config** unless the user specifies `--target-org`
- **Never deploy to production** without explicit confirmation; in CI mode, require the alias on the command line
- **Always verify source paths exist** before running the deploy command
- **Include Apex dependencies** automatically when deploying an LWC or React component
- **Include the matching test class** when deploying an Apex production class
- **Don't override `--no-mcp`.** If the user explicitly disables MCP routing for this deploy, honor it without warning
- **Append every run to deploy history** so `/argo:quick-deploy` can find the validation id later
- Report results clearly: components deployed, status, any errors
