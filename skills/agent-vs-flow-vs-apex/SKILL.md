---
name: agent-vs-flow-vs-apex
description: Decide whether a feature should be built as an Agentforce Agent, a Flow, an Apex Trigger, or other mechanism. Replaces /sf-dev-kit:flow-vs-apex when agents are in scope; otherwise falls through to it. Asks 6–10 questions and recommends with rationale.
data-access: none
---

You are extending the **flow-vs-apex** decision with **Agent** as a first-class option (Headless 360). Many things that used to be Flow + LWC + Apex are now better expressed as agents — especially conversational, multi-step, or reasoning-over-data workflows.

## When to use this vs /sf-dev-kit:flow-vs-apex

- **This skill** — when the project ships agents (`platform.frontend` includes agents OR `paths.agentDefinitions` is populated). Adds Agent to the decision space
- **`/sf-dev-kit:flow-vs-apex`** — when the project is non-agent. Same decisions but without the agent option

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
HAS_AGENTS="$(test -d \"$(sf_config_get '.paths.agentDefinitions // \"force-app/main/default/botDefinitions\"' "$ENV")\" && echo true || echo false)"
```

## Input

`$ARGUMENTS`:
- (empty) — interactive Q&A
- `<one-line description>` — interactive Q&A seeded with the description
- `--object <Object>` — concrete object context
- `--non-interactive answers="..."` — scripted

## Decision questions (in order; skip what's obvious from the description)

1. **What's the input?** record-trigger, schedule, user-button, conversational, platform-event, callout?
2. **Conversational? Multi-turn? Reasoning over org data with judgment?** (Strong agent signal)
3. **Volume — under 200 records / over 200 / 10K+?**
4. **Operation — field set / cross-object update / external callout / async / generative response?**
5. **Owner — admin team (declarative) or dev team (in source)?**
6. **Determinism — same input always same output? Or judgment / fuzzy ranking / explanation?**
7. **Confirmation needed before destructive action?**
8. **Sharing/security — must respect FLS, sharing, profile?**
9. **Latency — synchronous user wait acceptable / can be async?**
10. **Existing automation on the affected objects?** (Cross-reference `/sf-dev-kit:flow-audit` and `/sf-dev-kit:agent-discover`)

## Decision tree

```
Conversational, multi-step, OR generative response
  → Agent (Agentforce)
    With AGT-3 guardrails, AGT-5 FLS-aware grounding, AGT-7 escalation
    See agentforce pattern pack

Conversational, single-step ("look up X")
  → Either Agent OR LWC + Apex (SF-6)
    Choose Agent when:
      - User is already in Slack / mobile / non-Salesforce surface
      - Response benefits from reasoning (rephrasing the data, summarizing)
    Choose LWC + Apex when:
      - User is on a Salesforce record page
      - Response is a deterministic data render

Record-triggered, simple field updates, low volume, admin-owned
  → Flow

Record-triggered, complex / bulk / transaction control
  → Apex Trigger + TriggerHandler (SF-7)

Scheduled, large volume
  → Database.Batchable + Schedulable

External event in
  → Platform Event subscriber (Apex trigger on __e channel)

External callout out, transactional
  → Apex with Named Credential (SF-15)

External callout out, fire-and-forget
  → Queueable + Named Credential, with PRJ-6 static guard

Cross-system event broadcast
  → Platform Event publisher (or CDC if record-change)
```

### When to combine

- **Agent + Apex action** — most common pattern. Agent handles the conversational layer; Apex does the deterministic work. Bridge via `/sf-dev-kit:mcp-bridge` (AGT-4)
- **Agent + Flow** — agent calls a flow as an action. Reasonable when admins own the underlying workflow
- **LWC + Agent** — LWC embeds an agent for a specific interactive surface (e.g., a help chat in a record page). Use the LWC's `<lightning-agent-chat>` shell

## Output

```
# Choice: <one-line description>

## Answers
- Input:                conversational (Slack mention)
- Multi-step:           yes (lookup → confirm → cancel)
- Volume:               low (one user / one order at a time)
- Operation:            cross-object lookup + update + side-effect notification
- Owner:                dev team
- Determinism:          mostly deterministic, but the response phrasing is generative
- Confirmation:         yes — before cancellation
- Sharing:              must respect FLS (user can only cancel their own orders)
- Latency:              async OK (Slack)
- Existing:             no Flow on Order__c; Apex trigger handles legacy fields

## Recommendation: **Agent (Agentforce)** with Apex actions via MCP bridge

### Why
- Multi-turn conversational shape — Slack message → confirm → action — fits an agent perfectly
- Generative response phrasing rules out a pure Flow
- FLS requirement is satisfied via AGT-5 (WITH USER_MODE on grounding) and AGT-3 (output validation against the data the agent is allowed to see)
- Coexists cleanly with the existing Apex trigger; the agent invokes a different action path

### Implementation outline
- @architect: produce the design (agent topics + Apex actions + Slack manifest)
- @agent-dev: author /sf-dev-kit:agent-spec for order_helper, generate AgentDefinition
- @apex-dev: implement OrderApiClient.fetchOrder + cancelOrder; bridge via /sf-dev-kit:mcp-bridge
- @qa: write Apex tests; @agent-dev: write 12+ eval cases including 3 jailbreak scenarios
- /sf-dev-kit:slack-agent: scaffold the Slack delivery surface
- /sf-dev-kit:trust-layer-audit + /sf-dev-kit:agent-test: gate before deploy

### Patterns referenced
- AGT-1, AGT-3, AGT-4, AGT-5, AGT-7 (agentforce pack)
- SF-15 (HTTP callout via Named Credential — for any external touch)
- SF-16 (Apex REST service — bridged via /sf-dev-kit:mcp-bridge)

### Alternatives considered
- **Pure Apex + LWC**: would work in the Salesforce UI but doesn't reach the Slack surface
- **Flow + Slack notification**: Flow can post Slack messages, but the conversational follow-up needs reasoning — back to needing an agent
- **Slack workflow builder only**: limited to deterministic flows; can't handle "what about the order from last Tuesday?"-style imprecise queries
```

## Rules

- **Default to "not an agent"** if the work is deterministic + record-triggered + low-volume. Agents have higher ops cost (Trust Layer, evals, gateway, listing reviews); use them when the conversational/generative shape genuinely benefits
- **Always cite cross-object impact.** Existing Flows + Apex triggers on the same objects coexist with agents but the order of execution matters — call it out
- **Don't recommend "everything as agents".** Salesforce's own guidance: deterministic logic stays in Apex/Flow; agents add the conversational and reasoning layer
- **Show alternatives.** The user knows their constraints; surface 1-2 paths so they can push back

## Consumers

- `@architect` invokes this when a feature might involve agents
- `@agent-dev` reads the recommendation as the seed for `/sf-dev-kit:agent-spec`
- Project ADRs (`/sf-dev-kit:adr`) capture the choice for future teammates
