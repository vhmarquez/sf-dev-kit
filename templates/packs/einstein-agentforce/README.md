# Einstein / Agentforce Pack — DEPRECATED, renamed to `agentforce`

> **This stub was superseded in v2.5 (Phase 17).** The full content lives in [`templates/packs/agentforce/`](../agentforce/).
> The `einstein-agentforce` directory is kept for back-compat with installed projects that pinned the old name; it ships **no patterns**. Subsequent v3.x or later releases may remove it entirely.

## Migrate

```text
/sf-dev-kit:pattern-pack remove einstein-agentforce
/sf-dev-kit:pattern-pack add agentforce
```

The new pack ships AGT-1..7 (topic boundaries, sub-agent decomposition, guardrails, MCP-tool actions, FLS-aware grounding, memory & state, escalation paths) plus 8 quality-checklist additions.

## Why renamed

- "Einstein" is a broader Salesforce brand; "Agentforce" specifically names the agent surface this pack covers
- Aligns with the Headless 360 pattern-prefix convention (`AGT-*` for agent patterns)
- Reserves `EIN-*` for future Einstein-Discovery, Einstein-Vision, or Einstein-Bots packs that don't overlap with the agent surface
