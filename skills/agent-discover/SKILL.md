---
name: agent-discover
description: Inventory Agentforce agents in the project — both source-controlled `AgentDefinition` files and live agents in the target org. Maps each agent's topics, sub-agents, MCP tools used, and bridge tools registered. Counterpart to /flow-audit for the agent surface.
---

You are inventorying **agents** for the project. Agents are now first-class deployable artifacts (Headless 360); like Flows and Apex, they live in source control under `force-app/main/default/botDefinitions/` and are also visible in the org's Agent Registry. This skill reconciles the two.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/mcp.sh"
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
```

The conventional path for AgentDefinition metadata in DX is `<packageDir>/main/default/botDefinitions/<AgentName>/`. If a project uses a non-standard layout, set `paths.agentDefinitions` in `sf-project.json` and this skill reads from there.

## Input

`$ARGUMENTS`:
- (empty) — full inventory
- `<AgentName>` — focus on a single agent (source + org reconciliation)
- `--source-only` — only walk source; skip org queries
- `--org-only` — only query the org; skip source
- `--ci` / `--format json|sarif` / `--out <path>`

## Steps

### 1. Walk source

```bash
AGENT_DIR="$(sf_config_get '.paths.agentDefinitions // empty' "$ENV")"
[[ -z "$AGENT_DIR" ]] && AGENT_DIR="force-app/main/default/botDefinitions"
```

For each `<AgentName>/` subdirectory, parse:
- `<AgentName>.botDefinition-meta.xml` — top-level definition
- `<AgentName>.botVersion-meta.xml` — version metadata, active flag
- `topics/*.topic-meta.xml` — topic boundaries (one .topic file per topic)
- `actions/*.action-meta.xml` — bound actions (Apex, Flow, prompt template, MCP tool)
- `subAgents/*.subAgent-meta.xml` — sub-agent declarations

Capture for each agent:
```json
{
  "name": "Order_Helper",
  "label": "Order Helper",
  "isActive": true,
  "topics": ["lookup_order", "create_order", "cancel_order"],
  "subAgents": ["Order_Cancel_Specialist"],
  "actions": [
    {"name": "order_get", "kind": "mcp-tool"},
    {"name": "OrderApiClient.fetchOrder", "kind": "apex"},
    {"name": "Order_Email_Send", "kind": "flow"}
  ],
  "guardrails": ["No destructive ops without confirmation", "Don't reveal customer PII"],
  "source": "force-app/main/default/botDefinitions/Order_Helper/"
}
```

### 2. Query the org (if not `--source-only`)

Prefer MCP routing if available:
```bash
if mcp_prefer; then
  mcp_run data soql-query '{"soql":"SELECT Id, MasterLabel, DeveloperName, Status FROM AgentDefinition","org":"'"$ORG"'"}'
else
  sf data query --target-org "$ORG" --query "SELECT Id, MasterLabel, DeveloperName, Status FROM AgentDefinition" --json
fi
```

Also query:
- `AgentVersion` — version + activation history
- `AgentTopic` — topics per agent
- `AgentRegistryEntry` (or via `/sf-dev-kit:mcp-setup` Registry endpoint) — externally-discoverable tools

### 3. Reconcile

For each agent, classify:
| State | Meaning |
|-------|---------|
| ✅ in source AND active in org | tracked |
| ⚠️ in source AND inactive in org | source-only / draft |
| ⚠️ active in org NOT in source | untracked (won't deploy elsewhere; missing from CI/CD) |
| ⚠️ in source but org has newer version | drift — run `/sf-dev-kit:org-diff` to inspect |

### 4. Output

Default Markdown:
```
# Agent Discover: <project.name> @ <ORG>

Run at: 2026-04-28T16:30:00Z
Agent definitions in source: 4
Active agents in org: 5
MCP bridges registered: 8 (see /sf-dev-kit:mcp-bridge)

## Tracked agents

| Agent | Source | Org | Topics | Sub-agents | Actions | Status |
|-------|--------|-----|--------|------------|---------|--------|
| Order_Helper | ✅ | ✅ active v3 | 3 | 1 | 5 | tracked |
| Support_Triage | ✅ | ✅ active v1 | 4 | 0 | 7 | tracked |
| Knowledge_Search | ✅ | ⚠️ inactive | 2 | 0 | 3 | source-only |
| Onboarding_Bot | ✅ | ⚠️ org has v2; source v1 | 5 | 0 | 4 | drift |

## Untracked agents (active in org, not in source)

| Agent | Org Version | Modified by | Last modified |
|-------|-------------|-------------|---------------|
| Legacy_Sales_Coach | v8 | gov-user | 2026-03-12 |

## MCP tool surface

| Tool | Source | Used by |
|------|--------|---------|
| order_get | mcp/bridges/order_get.json | Order_Helper |
| order_post | mcp/bridges/order_post.json | Order_Helper |
| ticket_search | (managed package) | Support_Triage |
| ... |

## Findings

### High
- **Onboarding_Bot drift**: org has v2 but source has v1. Run `/sf-dev-kit:org-diff` to inspect. Prefer the org version (`sf project retrieve start`) or the source version (deploy + activate)

### Medium
- **Legacy_Sales_Coach untracked**: live in production but no source representation. Decide: retrieve into source (`sf project retrieve start`) or retire via `/sf-dev-kit:destructive-changes`
```

CI mode emits:
- One finding per untracked agent: `ruleId: "AGENT-UNTRACKED"` (warning)
- One finding per drifted agent: `ruleId: "AGENT-DRIFT"` (warning)
- One finding per active source-only agent: `ruleId: "AGENT-INACTIVE"` (note)

### 5. Exit codes
- 0 — no findings
- 1 — any finding
- 2 — config / query error

## Rules

- **Don't read agent prompts in detail.** Topic & action enumeration is enough; full prompt diffing belongs in `/sf-dev-kit:org-diff` or a code review
- **Honor managed-package agents.** Agents owned by an installed package are reported in a separate "From Managed Packages" section, not as findings
- **Cross-link to /sf-dev-kit:mcp-bridge.** When an agent uses a bridge tool, surface the bridge file path so reviewers can audit both sides
- **Don't auto-resolve drift.** Report; the user picks retrieve vs. deploy

## Consumers

- `@architect`, `@agent-dev`: read the source-side inventory before planning a new agent (avoid topic collisions)
- `/sf-dev-kit:flow-audit`: paired view — Flows AND agents on the same record-triggered surface need careful coexistence
- `/sf-dev-kit:release-notes`: groups new/modified agents into a "Agents" section
