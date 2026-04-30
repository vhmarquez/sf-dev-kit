---
name: agent-exchange-list
description: Validate readiness for AgentExchange listing. Checks required metadata, eval coverage, Trust Layer config, license boundaries, and listing artifacts (icon, screenshots, install URL). Reports a severity-graded readiness report so submission isn't a back-and-forth.
data-access: none
---

You are pre-validating an agent for **AgentExchange** listing. AgentExchange consolidated AppExchange + Slack Marketplace + the Agentforce ecosystem in TDX 2026; listings have stricter requirements than internal agents (icon, screenshots, security review, license boundaries, OAuth scopes review).

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
AGENT_DIR="$(sf_config_get '.paths.agentDefinitions // \"force-app/main/default/botDefinitions\"' "$ENV")"
```

## Input

`$ARGUMENTS`:
- `<agent-name>` — required
- `--listing-dir <path>` — directory containing listing artifacts (default `listings/<agent-name>/`)
- `--ci` / `--format json|sarif` / `--out <path>` / `--fail-on error|warning`

## Listing requirements

### Mandatory

| Check | Severity if fail | Rule ID |
|-------|------------------|---------|
| Agent has been deployed and is currently `Active` in at least one org | error | `LIST-AGENT-NOT-ACTIVE` |
| Eval suite ≥ 10 cases (vs ≥5 for internal agents) | error | `LIST-EVAL-THIN` |
| Eval suite includes ≥ 2 prompt-injection / jailbreak cases | error | `LIST-EVAL-NO-JAILBREAK` |
| Latest `/argo:agent-test` run scored ≥ 0.92 overall (vs 0.85 internal) | error | `LIST-EVAL-LOW-SCORE` |
| Latest `/argo:trust-layer-audit` exits 0 | error | `LIST-TRUST-AUDIT-FAILED` |
| Listing icon at `<listing-dir>/icon.png` (256×256, ≤200 KB) | error | `LIST-NO-ICON` |
| Listing screenshots at `<listing-dir>/screenshots/*.png` (≥3, max 1 MB each) | error | `LIST-NO-SCREENSHOTS` |
| Listing description at `<listing-dir>/description.md` (≥200 chars, ≤1000) | error | `LIST-NO-DESCRIPTION` |
| Privacy notice at `<listing-dir>/privacy.md` describing data handling | error | `LIST-NO-PRIVACY` |
| OAuth scopes documented at `<listing-dir>/scopes.md` with justification per scope | error | `LIST-NO-SCOPES` |
| All MCP bridge tools used by the agent have `outputSchema` defined | error | `LIST-TOOL-NO-SCHEMA` |
| No `without sharing` Apex reachable from any agent action | error | `LIST-WITHOUT-SHARING-EXPOSED` |
| API version on AgentDefinition matches `platform.apiVersion` AND is ≤ 2 versions behind current Salesforce release | warning | `LIST-API-VERSION-OLD` |

### Recommended

| Check | Severity | Rule ID |
|-------|----------|---------|
| Agent has a sub-agent for any topic with > 3 actions (decomposition; AGT-2) | warning | `LIST-MISSING-DECOMPOSITION` |
| Documented escalation path with concrete user response template (AGT-7) | warning | `LIST-WEAK-ESCALATION` |
| Memory pattern documented (Curated vs custom Agent_Conversation__c; AGT-6) | warning | `LIST-NO-MEMORY-DOC` |
| Coverage of `/argo:trust-eval` runtime metrics in privacy.md | warning | `LIST-NO-RUNTIME-DISCLOSURE` |
| Demo video (linked in description.md) | note | `LIST-NO-VIDEO` |
| Per-edition compatibility matrix in description.md | note | `LIST-NO-EDITION-MATRIX` |

## Steps

### 1. Run prerequisite skills

```bash
/argo:agent-test "$NAME" --ci --format json --out /tmp/list-eval.json     || true
/argo:trust-layer-audit "$NAME" --ci --format json --out /tmp/list-trust.json || true
/argo:agent-discover "$NAME" --ci --format json --out /tmp/list-disc.json    || true
/argo:fls-audit --ci --format json --out /tmp/list-fls.json                  || true
/argo:sharing-review --ci --format json --out /tmp/list-share.json           || true
```

### 2. Validate listing artifacts

```bash
LISTING_DIR="${LISTING_DIR:-listings/${NAME}}"
[[ -d "$LISTING_DIR" ]] || { findings+=( $(emit LIST-NO-DIR error "Missing $LISTING_DIR") ); }

[[ -f "$LISTING_DIR/icon.png" ]] && check_dimensions "$LISTING_DIR/icon.png" 256 256 || findings+=( ... )
[[ -d "$LISTING_DIR/screenshots" ]] && [[ $(ls "$LISTING_DIR/screenshots" | wc -l) -ge 3 ]] || ...
[[ -f "$LISTING_DIR/description.md" ]] && check_length "$LISTING_DIR/description.md" 200 1000 || ...
[[ -f "$LISTING_DIR/privacy.md" ]] || ...
[[ -f "$LISTING_DIR/scopes.md" ]] || ...
```

### 3. Cross-check eval coverage

Parse `/tmp/list-eval.json` for case count + jailbreak case count + overall score.

### 4. Cross-check security findings

Parse `/tmp/list-fls.json` and `/tmp/list-share.json` — any `error`-level finding promotes to `LIST-WITHOUT-SHARING-EXPOSED` or its FLS sibling.

### 5. Output

Default Markdown:
```
# AgentExchange Listing Readiness: order_helper

Run at: 2026-04-28T19:30:00Z
Listing dir: listings/order_helper

## Mandatory checks

✅ Agent active in DevVM
✅ Eval suite: 12 cases (≥10 required)
✅ Eval jailbreak cases: 3 (≥2 required)
✅ Eval overall score: 0.94 (≥0.92 required)
✅ Trust Layer audit: 0 findings
⚠️ Listing icon: missing (LIST-NO-ICON)
⚠️ Listing screenshots: only 2 (need 3) (LIST-NO-SCREENSHOTS)
✅ Description: 380 chars
✅ Privacy notice: present
⚠️ OAuth scopes: scopes.md missing (LIST-NO-SCOPES)
✅ Tool output schemas: all 5 bridges have outputSchema
✅ Sharing: no without-sharing exposed via agent actions
✅ API version: 66.0 (current)

## Recommended

⚠️ Missing decomposition: cancel_order topic has 3 actions (LIST-MISSING-DECOMPOSITION)
✅ Escalation path documented in description.md
✅ Memory pattern: Agent_Conversation__c documented in privacy.md

## Verdict

❌ NOT READY for AgentExchange submission.

Critical fixes required:
- Add listings/order_helper/icon.png (256×256, ≤200 KB)
- Add a third screenshot to listings/order_helper/screenshots/
- Author listings/order_helper/scopes.md with per-scope justification

Recommended fixes (not blocking submission, but Salesforce reviewers may request):
- Decompose cancel_order topic into a sub-agent (AGT-2)

## Submission checklist (after fixes)

1. Re-run /argo:agent-exchange-list <name> --ci --fail-on error → exits 0
2. Re-run /argo:trust-layer-audit and /argo:trust-eval → no regression
3. Submit via the AgentExchange portal: https://agentexchange.salesforce.com/publish
4. Expect a security review (~5-10 business days)
```

CI mode: SARIF per finding.

## Exit codes
- 0 — listing-ready (no `--fail-on` violations)
- 1 — issues exist
- 2 — invocation error

## Rules

- **Don't auto-create listing artifacts.** Icons, screenshots, descriptions are content the human must produce. The skill checks they exist; doesn't generate them
- **Don't submit on the user's behalf.** AgentExchange submission is a user-driven step via the portal. The skill prepares; humans submit
- **Mandatory rules are stricter than internal-agent rules.** A listed agent runs in customer orgs you don't control — the bar is higher
- **OAuth scopes require justification.** A reviewer reads scopes.md to understand why your agent asks for `chat:write` (etc.). Don't list scopes without explaining why each is needed
