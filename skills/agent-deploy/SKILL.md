---
name: agent-deploy
description: Deploy AgentDefinition metadata + register the eval suite with Testing Center, with Trust Layer + eval-regression gating. Refuses to deploy if /argo:trust-layer-audit or /argo:agent-test fail.
data-access: metadata-only
---

You are deploying an **agent** — AgentDefinition + AgentVersion + topics + actions + sub-agents — and registering its eval suite with Testing Center so future runs are tracked. This is the agent-side counterpart to `/argo:diff-deploy` for code.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/sf-cli.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/mcp.sh"
sf_cli_check || exit 2
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
AGENT_DIR="$(sf_config_get '.paths.agentDefinitions // empty' "$ENV")"
[[ -z "$AGENT_DIR" ]] && AGENT_DIR="force-app/main/default/botDefinitions"
```

## Input

`$ARGUMENTS`:
- `<agent-name>` — deploy this agent (must exist under `<AGENT_DIR>/<name>/`)
- `--validate` — dry-run via `sf project deploy start --dry-run`
- `--skip-evals` — deploy without running eval gates (NOT recommended; emits a warning)
- `--skip-trust` — skip `/argo:trust-layer-audit` (NOT recommended; emits a warning)
- `--target-org <alias>` / `--env <name>` — overrides
- `--ci` — machine output

## Pre-deploy gates

The skill refuses to deploy unless the following pass (or are explicitly skipped with the `--skip-*` flags):

1. **Trust Layer audit** — `/argo:trust-layer-audit <agent-name> --ci` exits 0
2. **Eval suite passes** — `/argo:agent-test <agent-name> --ci --fail-on error` exits 0
3. **Eval-regression check vs. main** — `/argo:agent-eval-trend pr <agent-name>` exits 0
4. **Agent discoverable** — `/argo:agent-discover <agent-name> --ci` confirms source exists

If any fails, emit a `[agent-deploy] BLOCKED` message with the failing gate name and the underlying skill's output.

## Steps

### 1. Resolve agent path
```bash
AGENT_PATH="${AGENT_DIR}/${NAME}"
[[ -d "$AGENT_PATH" ]] || { echo "[agent-deploy] not found: ${AGENT_PATH}" >&2; exit 2; }
```

### 2. Run the gates (unless skipped)

```bash
gate_trust=0; gate_eval=0; gate_trend=0
[[ "$SKIP_TRUST" != "1" ]] && /argo:trust-layer-audit "$NAME" --ci || gate_trust=$?
[[ "$SKIP_EVALS" != "1" ]] && /argo:agent-test "$NAME" --ci --fail-on error || gate_eval=$?
[[ "$SKIP_EVALS" != "1" ]] && /argo:agent-eval-trend pr "$NAME" || gate_trend=$?

if (( gate_trust + gate_eval + gate_trend > 0 )); then
  echo "[agent-deploy] BLOCKED: gates failed (trust=${gate_trust} eval=${gate_eval} trend=${gate_trend})" >&2
  exit 1
fi
```

(If `--validate`, the gates still run — better to know early; the deploy itself is the dry-run.)

### 3. Deploy the agent metadata

Bundle every file under the agent directory plus any cross-referenced bridge specs:
```bash
SOURCES=("$AGENT_PATH")
# If actions reference MCP bridges, include them in the deploy
for spec in mcp/bridges/*.json; do
  if grep -lqE "$(basename "$spec" .json)" "${AGENT_PATH}/actions"/*.action-meta.xml 2>/dev/null; then
    SOURCES+=("$spec")
  fi
done

sf project deploy start \
  --target-org "$ORG" \
  ${VALIDATE:+--dry-run} \
  $(printf -- "--source-dir %q " "${SOURCES[@]}") \
  --wait 30 \
  --json
```

### 4. Register eval suite with Testing Center

After a successful (non-validate) deploy, register evals:

```bash
if mcp_prefer; then
  for case_file in tests/agent-evals/${NAME}/*.json; do
    mcp_run testing register-eval "$(jq -c --arg agent "$NAME" --arg path "$case_file" '. + {agent:$agent, sourcePath:$path}' "$case_file")"
  done
else
  for case_file in tests/agent-evals/${NAME}/*.json; do
    sf agent test register-case --target-org "$ORG" --agent "$NAME" --file "$case_file" --json
  done
fi
```

This makes the eval suite visible in the Testing Center UI for ongoing monitoring.

### 5. Activate the new version

By default, deploys produce an **inactive** new AgentVersion. The deploy step does NOT auto-activate — operators activate via Setup or via:

```bash
sf data update record \
  --target-org "$ORG" \
  --sobject AgentVersion \
  --where "BotDefinitionDeveloperName='${NAME}' AND VersionNumber=$(latest_version)" \
  --values "Status='Active'"
```

The skill prints the activation command rather than running it. Activation is an explicit operator decision that should not be automated by default.

### 6. Append to deploy history

```bash
echo '{"deployedAt":"...","org":"...","agent":"'"$NAME"'","version":"v3","validate":'"$VALIDATE"'}' \
  >> "${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugin-data}/argo/agent-deploys/<project>/history.jsonl"
```

### 7. Output

Default Markdown:
```
# Agent Deploy: order_helper

Pre-deploy gates:
✅ Trust Layer audit:    0 findings
✅ Eval suite:           8/8 passed (0.91 overall)
✅ Eval regression:      no regressions vs main
✅ Agent discover:       source verified

Deploy:
✅ AgentDefinition + 3 topics + 5 actions + 1 sub-agent + 2 MCP bridge specs
   Org: DevVM
   Mode: dry-run (--validate)  [or:  applied (12.4s)]

Eval registration with Testing Center:
✅ 8 cases registered for ongoing monitoring

## To activate the new version:
sf data update record --target-org DevVM --sobject AgentVersion ... \
  --values "Status='Active'"

## Or via Setup
Setup → Agents → order_helper → Versions → "Activate" on v3
```

CI mode JSON: `{"agent":"order_helper","gates":{"trust":"pass","evals":"pass","regression":"pass"},"deployId":"0Af...","validateOnly":false,"casesRegistered":8}`.

### 8. Exit codes
- 0 — deploy succeeded (or validate succeeded)
- 1 — gate failed OR deploy itself failed
- 2 — invocation error

## Rules

- **Don't activate by default.** Activation routes user traffic to the new version; operators control that. Skill prints the command, doesn't run it
- **Always include bridge specs when actions reference them.** Otherwise the deployed agent has actions pointing at tools the org doesn't know about
- **Skip flags emit warnings.** `--skip-trust` and `--skip-evals` are escape hatches for emergencies, not standard practice. The output makes that clear
- **Dry-run honors gates too.** Knowing the gates would have blocked is valuable even when validating
- **Per-env activation status.** Activate dev → run smoke evals → activate prod, sequentially. Don't activate everywhere at once
