---
name: devops-natural
description: Natural-language deploy via the DevOps Center MCP toolset (Headless 360). Wraps an English description like "deploy the order changes from main to QA" into a structured deploy. Falls back to /argo:diff-deploy when MCP isn't configured.
data-access: metadata-only
---

You are translating a natural-language deploy request into a concrete deploy via the DevOps Center MCP. Salesforce reports up to 40% cycle-time reduction over CLI-driven deploys when the right toolset is configured. This skill is a thin opinionated wrapper that adds project-context-aware prompts and gating.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/mcp.sh"
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
TOOLSETS="$(mcp_configured_toolsets "$ENV")"

case ",$TOOLSETS," in
  *,devops,*) ;;
  *) echo "[devops-natural] devops toolset not enabled. Run: /argo:mcp-setup --toolsets metadata,devops"; exit 2 ;;
esac
```

## Input

`$ARGUMENTS`: required — the natural-language request.

Examples:
- `"deploy the order changes since main to DevSandbox"` → equivalent to `/argo:diff-deploy --vs main --target-org DevSandbox`
- `"validate everything against prod"` → `--validate --target-org Prod`
- `"deploy only the LWC components touched today"` → diff-since-today filtered to LWC bundles
- `"promote v1.4.0-beta.7 to released"` → `/argo:package-version promote 04t...`
- `"roll back the last deploy"` → builds destructive changes from the last deploy log; not auto-applied
- `--dry-run` — show what would happen, don't execute
- `--ci` — non-interactive; the natural-language input must be unambiguous

## Steps

### 1. Parse intent via DevOps MCP

```bash
mcp_run devops parse-deploy-request "$(jq -nc --arg text "$REQUEST" --arg org "$ORG" '{text: $text, defaultOrg: $org}')"
```

The DevOps MCP returns a structured plan:
```json
{
  "intent": "diff-deploy",
  "vs": "main",
  "targetOrg": "DevSandbox",
  "scope": {
    "metadata": ["LightningComponentBundle", "ApexClass"],
    "filter": "modified since main"
  },
  "validateOnly": false,
  "estimatedComponents": 12,
  "estimatedDurationSeconds": 90,
  "warnings": []
}
```

### 2. Surface the plan to the user (always, even in CI mode)

```
[devops-natural] Parsed:
  Intent:        diff-deploy
  Source:        force-app/ (12 changed components since main)
  Target:        DevSandbox
  Validate-only: false
  Est. duration: ~90s

This will:
  - Deploy 7 LWC bundles + 5 Apex classes
  - Run tests for the 5 production classes (RunSpecifiedTests)
  - Append the deploy id to ${CLAUDE_PLUGIN_DATA}/argo/deploys/<project>/history.jsonl

Proceed? (y/N)
```

In CI mode, proceed if the plan has no warnings AND the user passed `--auto-approve`. Otherwise abort with the plan as output.

### 3. Map to a argo skill

Based on `intent`, dispatch to the right structured skill:
| Intent | Skill |
|--------|-------|
| `diff-deploy` | `/argo:diff-deploy --vs <ref> --target-org <org>` |
| `full-deploy` | `/argo:deploy <path> --target-org <org>` |
| `quick-deploy` | `/argo:quick-deploy <id>` |
| `validate-only` | (above with `--validate`) |
| `package-promote` | `/argo:package-version promote <id>` |
| `rollback` | `/argo:destructive-changes` (interactive) |
| `agent-deploy` | `/argo:agent-deploy <agent>` |

This skill never invokes `sf project deploy start` directly — it routes through the structured skills so deploy history, gates, and notifications stay consistent.

### 4. Run, capture, report

```bash
$CHILD_SKILL  # the dispatched skill
deploy_exit=$?
```

Append the natural-language request to the deploy history alongside the structured deploy id, so `/release-notes` can quote the original phrasing in the changelog.

## Output

```
# DevOps Natural Deploy

Request:    "deploy the order changes since main to DevSandbox"
Parsed as:  diff-deploy --vs main --target-org DevSandbox
Result:     ✅ Deploy 0Af...XYZ succeeded (87.4s)
            12 components, 23 tests passed
History:    appended to ${CLAUDE_PLUGIN_DATA}/.../deploys.jsonl
```

CI JSON: `{"request":"...","intent":"diff-deploy","deployId":"0Af...XYZ","status":"Succeeded","durationSeconds":87}`.

## Exit codes
- 0 — deploy succeeded
- 1 — deploy failed (the dispatched skill's exit code passes through)
- 2 — couldn't parse intent / devops toolset not configured

## Rules

- **Don't replace the structured skills.** This skill *parses* and *dispatches*; it never deploys directly. Keeps deploy history consistent and gates intact
- **Always show the parsed plan.** Natural language is ambiguous; the user confirms before destructive actions. CI runs require `--auto-approve` to skip the prompt
- **Refuse on ambiguity.** If the DevOps MCP returns multiple plausible intents or a confidence below threshold, surface the alternatives and bail out with exit 2
- **Don't auto-rollback.** "Roll back" requests build the destructive-changes manifest but require manual review before applying

## Consumers

- Interactive devs: faster than remembering exact CLI flags
- Slack-deploy bots (paired with `/argo:slack-agent`): "@deploy-bot push the order changes to QA" → invokes this skill from Slack
- Onboarding: new devs ramp without learning every flag
