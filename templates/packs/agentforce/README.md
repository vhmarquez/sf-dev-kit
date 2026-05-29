# Agentforce Pack

Patterns and guidance for building production Salesforce **Agentforce** agents — the platform's agent surface.

## When to use this pack

Install with `/argo:pattern-pack add agentforce` if your project:
- Ships customer-facing or internal agents (defined under `botDefinitions/`)
- Calls Apex from agent actions
- Exposes Apex REST endpoints as MCP tools that the agent calls at runtime
- Has a defined Trust Layer audit posture (run `/argo:trust-layer-audit`)

If you're not yet building agents, defer — the base SF-1..20 patterns plus the integration patterns are enough.

## What's in the pack

- **AGT-1: Topic Boundaries** — one intent cluster per topic, ≤2 actions
- **AGT-2: Sub-agent Decomposition** — when and how to split a topic out
- **AGT-3: Guardrails** — input + output validation, refusal hardening, prompt-injection resistance
- **AGT-4: Action via MCP Tool** — bridging Apex REST as agent tools (SF-16)
- **AGT-5: Grounding with FLS** — `WITH USER_MODE` on every grounding query; output schemas
- **AGT-6: Memory & State** — Curated Memory + custom `Agent_Conversation__c` patterns
- **AGT-7: Escalation Paths** — `escalate_to_human` topic, Case creation, Slack handoff

Plus the eight quality-checklist items appended to `docs/quality-checklist.md` covering: prompt safety, topic boundaries, eval-suite minimums, AI Gateway hooks.

## What's not in the pack

- Trust Layer config — that's `/argo:trust-layer-audit`
- Agent eval drift — that's `/argo:agent-eval-trend`
- AI Gateway tuning — that's `/argo:gateway-config`
- Slack-specific agent assembly — see `slack-agent` pack (Phase 18)

This pack is the *design* knowledge. The skills above are the *runtime* tooling.

## Cross-references

- Base patterns: SF-15 (Named Credentials), SF-16 (Apex REST), SF-17 (Custom Metadata)
- Specialist agents: `@agent-dev`, `@trust-reviewer`
- Skills: `/argo:agent-spec`, `/argo:agent-test`, `/argo:agent-deploy`, `/argo:trust-layer-audit`
- Standards: the Agent section appended to `docs/quality-checklist.md`

## References

- [Agentforce documentation](https://help.salesforce.com/s/articleView?id=sf.agent_topics.htm)
- [Agent Script (open-sourced) reference](https://github.com/salesforcecli/agent-script)
- [Einstein Trust Layer](https://help.salesforce.com/s/articleView?id=sf.einstein_trust_layer.htm)
- [OWASP Top 10 for LLM Applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/)
