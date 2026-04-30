---
name: gateway-config
description: Generate (or validate) the LLM Governance on AI Gateway configuration for the project — token quotas, model allowlist, fallback policy, per-agent rate limits. Output is a `.claude/ai-gateway.<env>.json` file the org's gateway service consumes.
data-access: none
---

You are producing the **AI Gateway** configuration that controls token usage, model selection, and fallback behavior for agents in this org. The gateway is the org-level chokepoint for LLM traffic — sensible defaults here prevent surprise bills and cap blast-radius for misbehaving agents.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
PROJECT_NAME="$(sf_config_get '.project.name' "$ENV")"
DEFAULT_ENV="${ENV:-base}"
```

The output path follows the env-override convention:
- `--env prod` → writes `.claude/ai-gateway.prod.json`
- (no env) → writes `.claude/ai-gateway.json` (the base config)

Per-env overrides deep-merge over the base in the same way `sf-project.<env>.json` does.

## Input

`$ARGUMENTS`:
- (empty) — interactive walk through the sections below
- `--profile dev|qa|prod` — apply a recommended bundle (see below)
- `--validate` — verify the existing gateway config; no changes
- `--env <name>` — write to env override file
- `--ci` — non-interactive, profile or explicit fields required

## Configuration sections

### Models

| Field | Purpose | Default |
|-------|---------|---------|
| `models.allowlist` | Models permitted from this org | `["sf-proprietary","claude-sonnet","gpt-5"]` |
| `models.default` | Default for non-specialized work | `"sf-proprietary"` |
| `models.byAgent` | Per-agent model override | `{}` |

### Quotas

| Field | Purpose | Default (dev / prod) |
|-------|---------|----------------------|
| `quotas.tokensPerHour.org` | Org-wide ceiling | `1_000_000 / 10_000_000` |
| `quotas.tokensPerHour.perAgent` | Per-agent ceiling | `100_000 / 1_000_000` |
| `quotas.requestsPerMinute.perAgent` | Per-agent rate limit | `60 / 600` |
| `quotas.maxContextTokens` | Per-request context cap | `100_000` |
| `quotas.maxOutputTokens` | Per-response output cap | `4_096` |

### Fallback

| Field | Purpose | Default |
|-------|---------|---------|
| `fallback.policy` | What to do when primary model fails or quota exceeded | `"degrade"` (use cheaper model) |
| `fallback.chain` | Ordered fallback list | `["claude-sonnet","gpt-5","sf-proprietary"]` |
| `fallback.refuseAfter` | Stop trying after N attempts | `3` |
| `fallback.userMessage` | Message shown when refusing | `"I'm temporarily unavailable. Please try again in a minute."` |

### Audit

| Field | Purpose | Default |
|-------|---------|---------|
| `audit.logAllRequests` | Log every request for compliance | `true` |
| `audit.retainDays` | Log retention | `90` (dev) / `365` (prod) |
| `audit.alertWebhook` | Webhook for quota-exceeded events | (project's `notifications.webhooks.slack`) |

## Profiles

| Profile | Token / hour cap | Model | Audit retention |
|---------|------------------|-------|-----------------|
| `dev` | 1M | sf-proprietary (cheap, fast iteration) | 30d |
| `qa` | 5M | claude-sonnet | 60d |
| `prod` | 10M | claude-sonnet (with gpt-5 fallback) | 365d |

Each profile is a JSON template under `${CLAUDE_PLUGIN_ROOT}/templates/gateway/<profile>.json` (the skill copies + merges).

## Steps

### `--profile prod`

1. Read template `${CLAUDE_PLUGIN_ROOT}/templates/gateway/prod.json`
2. Substitute project-specific fields:
   - `audit.alertWebhook` ← `notifications.webhooks.slack` from sf-project.json
   - `models.byAgent` ← infer from `botDefinitions/` (if there are agents in source)
3. Write to `.claude/ai-gateway.prod.json`

### Interactive (no profile)

Walk through each section, showing defaults from the closest matching profile, asking the user to override or accept.

### `--validate`

1. Load current `.claude/ai-gateway[.<env>].json`
2. Cross-check against constraints:
   - Each agent in `botDefinitions/` is either in the allowlist or has a per-agent model override
   - Default model is in the allowlist
   - Fallback chain doesn't include disallowed models
   - Token quotas are positive and per-agent ≤ org-wide
   - `notifications.webhooks.slack` resolves (if used)
3. Report findings with rule IDs `GATEWAY-AGENT-NO-MODEL`, `GATEWAY-FALLBACK-DISALLOWED`, `GATEWAY-QUOTA-INVERTED`, etc.

## Output

Default Markdown after generate:
```
# AI Gateway Config: <project.name> (env=prod)

✅ Wrote .claude/ai-gateway.prod.json (merged template + project context)

Models:
- Allowlist:        claude-sonnet, gpt-5, sf-proprietary
- Default:          claude-sonnet
- Per-agent:        order_helper → claude-sonnet, support_triage → claude-sonnet

Quotas:
- Org tokens/hour:  10,000,000
- Per-agent:        1,000,000
- Per-agent rate:   600 req/min
- Max context:      100,000 tokens
- Max output:       4,096 tokens

Fallback:
- Policy:           degrade
- Chain:            claude-sonnet → gpt-5 → sf-proprietary → refuse
- Refuse after:     3 attempts

Audit:
- Log all:          true
- Retain:           365 days
- Alert webhook:    https://hooks.slack.com/... (from notifications.webhooks.slack)

## Next steps
- Apply via the org's AI Gateway admin (Setup → Einstein → AI Gateway → Import)
- Schedule periodic /sf-dev-kit:gateway-config --validate runs to detect drift
- Review /sf-dev-kit:trust-eval reports to tune token quotas based on actual usage
```

`--validate` output:
```
# Gateway Config Validation: <project.name> (env=prod)

✅ Allowlist:    valid
✅ Default model: in allowlist
✅ Fallback chain: in allowlist
⚠️ Per-agent override: support_triage references "claude-haiku" not in allowlist (GATEWAY-FALLBACK-DISALLOWED)
✅ Quotas:       per-agent ≤ org-wide
✅ Webhook:      resolves
```

## Exit codes
- 0 — config written or validate clean
- 1 — `--validate` found issues
- 2 — invocation error

## Rules

- **Don't write secrets.** Webhook URLs are sensitive; the file should reference `${SLACK_WEBHOOK_URL}` env var indirection rather than the literal URL where possible
- **Per-env scoping is normal.** dev caps low; prod caps high. Use override files
- **Don't auto-apply.** This skill writes config; an operator imports it into the org's Gateway. Don't try to PUT it via API automatically (gateway changes are operator decisions)
- **Validate before deploy.** Recommend running `--validate` on PR; failed validation blocks the merge in CI
- **Quotas are guardrails, not optimization.** Set them generously enough that legitimate users don't hit them, low enough that runaway agents can't drain credits

## Consumers

- Gateway operators (admins) import the JSON via Setup
- `/sf-dev-kit:agent-deploy` cross-references the agent against the gateway model allowlist; warns if a deployed agent references a non-allowed model
- `/sf-dev-kit:trust-eval` references quota-exceeded events captured in the audit log
