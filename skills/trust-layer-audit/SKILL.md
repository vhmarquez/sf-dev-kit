---
name: trust-layer-audit
description: Verify Einstein Trust Layer configuration for the target org and per-agent settings. Checks PII masking, FLS enforcement on grounding queries, zero-data-retention agreements with LLM providers, dynamic-grounding scope, and prompt-template safety. Severity-graded findings; SARIF for security pipelines.
data-access: metadata-only
---

You are auditing the **Einstein Trust Layer** for this org and the project's agents. The Trust Layer is Salesforce-managed but has org-level toggles (data masking, ZDR agreements with LLM providers) and per-agent / per-prompt configurations that drift over time. This skill is a static + org-side check.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/sf-cli.sh"
sf_cli_check || exit 2
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
AGENT_DIR="$(sf_config_get '.paths.agentDefinitions // empty' "$ENV")"
[[ -z "$AGENT_DIR" ]] && AGENT_DIR="force-app/main/default/botDefinitions"
```

## Input

`$ARGUMENTS`:
- (empty) — org-level audit + every agent in source
- `<agent-name>` — focus on one agent
- `--target-org <alias>` / `--env <name>` — overrides
- `--ci` / `--format json|sarif` / `--out <path>`
- `--fail-on error|warning|note` — minimum severity for exit 1 (default `error`)

## Audit checklist

### Org-level (run once per audit)

| Check | Severity if fail | Rule ID |
|-------|------------------|---------|
| Einstein Trust Layer feature enabled (`SetupAuditTrail` shows enablement OR `EinsteinPlatform` setting `IsEnabled = true`) | error | `TRUST-NOT-ENABLED` |
| Data masking active for PII fields (org-level setting + at least one PII pattern policy) | error | `TRUST-MASKING-OFF` |
| Zero-data-retention agreement signed with each configured LLM provider (queryable via `LLMProvider` / Trust Layer settings) | error | `TRUST-NO-ZDR` |
| Dynamic-grounding scope respects FLS (`EinsteinFeatureSetting.GroundingFlsEnforced = true`) | error | `TRUST-GROUNDING-FLS-OFF` |
| Audit log retention ≥ 30 days | warning | `TRUST-AUDIT-SHORT` |
| Toxicity / bias detection enabled on output | warning | `TRUST-TOXICITY-OFF` |

Query org-level settings via:
```bash
sf_cli_query "SELECT EinsteinTrustLayerEnabled, MaskingEnabled, GroundingFlsEnforced FROM Organization" "$ORG"
```

(Field names depend on the Salesforce release — fall back gracefully if a field doesn't exist; report it as a `TRUST-FIELD-UNKNOWN` note instead of erroring.)

### Per-agent (run for each agent in scope)

| Check | Severity | Rule ID |
|-------|----------|---------|
| All grounding SOQL in `actions/*.action-meta.xml` uses `WITH USER_MODE` | error | `TRUST-GROUNDING-NO-USER-MODE` |
| No hardcoded PII placeholders in prompt templates (no email patterns, no phone patterns, no SSN-shape strings) | error | `TRUST-PROMPT-PII` |
| No hardcoded org URLs or 18-char Salesforce IDs in prompt templates | warning | `TRUST-PROMPT-HARDCODED` |
| Customer-facing agents have an escalation topic | warning | `TRUST-NO-ESCALATION` |
| Eval suite includes ≥1 prompt-injection / jailbreak case | error | `TRUST-NO-JAILBREAK-EVAL` |
| Destructive actions wrapped in `confirm-before-execute` topic flow | warning | `TRUST-DESTRUCTIVE-NO-CONFIRM` |
| All bound MCP tools (`mcp/bridges/*.json`) have output schemas defined | warning | `TRUST-TOOL-NO-SCHEMA` |
| No prompt template asks the agent to "ignore previous instructions" or similar (would prime it for injection) | error | `TRUST-PROMPT-LEAKY` |

Static parse of agent files; do not invoke the LLM during audit.

### Source-side checks (no org access required)

| Check | Severity | Rule ID |
|-------|----------|---------|
| Agent declares all its actions in source (no implicit "discover at runtime" actions) | warning | `TRUST-IMPLICIT-ACTIONS` |
| Eval suite directory exists at `tests/agent-evals/<agent>/` with ≥5 cases | warning | `TRUST-THIN-EVAL` |
| Agent doc exists at `docs/agents/<agent>.md` | note | `TRUST-NO-DOC` |

## Output

Default Markdown:
```
# Trust Layer Audit: order_helper @ DevVM

Run at: 2026-04-28T18:00:00Z
Scope: 1 org-level + 1 agent

## Org-level

| Check | Status |
|-------|--------|
| Einstein Trust Layer enabled | ✅ |
| PII data masking active     | ✅ (4 patterns: email, phone, SSN, credit card) |
| ZDR with OpenAI             | ✅ signed 2026-01-14 |
| ZDR with Anthropic          | ⚠️ not configured (TRUST-NO-ZDR) |
| Grounding FLS enforced      | ✅ |
| Audit log retention         | ✅ 90 days |
| Toxicity detection          | ⚠️ off (TRUST-TOXICITY-OFF) |

## Agent: order_helper

| Check | Status |
|-------|--------|
| Grounding uses WITH USER_MODE | ✅ all 3 actions |
| No PII in prompts              | ✅ |
| No hardcoded org-specific values | ⚠️ "00D5g..." Salesforce ID found in escalate_to_human (TRUST-PROMPT-HARDCODED) |
| Escalation topic               | ✅ escalate_to_human |
| Jailbreak eval                 | ✅ tests/agent-evals/order_helper/jailbreak_pii_exfil.json |
| Destructive confirm            | ✅ cancel_order topic confirms first |
| MCP tool schemas               | ⚠️ order_post.json missing outputSchema (TRUST-TOOL-NO-SCHEMA) |
| Prompt-injection priming       | ✅ no leaky phrasing detected |

## Findings

### Critical (must fix)
- TRUST-NO-ZDR — Anthropic ZDR agreement not signed (org-level) — coordinate with security/legal

### High
- TRUST-PROMPT-HARDCODED — `botDefinitions/order_helper/topics/escalate_to_human.topic-meta.xml:42` contains a 15+18-char Salesforce ID; replace with a Custom-Metadata-driven config (SF-17)

### Medium
- TRUST-TOXICITY-OFF — enable Setup → Einstein → Trust Layer → Toxicity Detection
- TRUST-TOOL-NO-SCHEMA — `mcp/bridges/order_post.json` lacks `outputSchema`; add it

### Low
- (none)
```

CI mode: SARIF emit per finding. Exit 0 if no findings ≥ `--fail-on`; 1 otherwise.

## Exit codes
- 0 — clean (or all below `--fail-on`)
- 1 — findings ≥ `--fail-on`
- 2 — invocation / org access failure

## Rules

- **Don't bypass.** Trust Layer features are non-configurable per Salesforce policy; if a check shows as off, that's almost certainly a misconfigured org or a feature that hasn't propagated yet — escalate, don't suppress
- **Static checks first.** Don't query the org for things grep can answer (e.g., "does the agent's prompt template contain a Salesforce ID")
- **Don't run the LLM.** This is a config audit; eval-time behavior is `/argo:trust-eval`'s job
- **`/agent-deploy` runs this skill as a gate** by default (pass `--skip-trust` to opt out, but expect the deploy report to surface a warning)
- **Per-env audits.** Run with `--env prod` to audit prod config; thresholds may be tighter (`quality.agentEvalThreshold` higher)
