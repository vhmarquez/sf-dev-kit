<!--
  This pack is DEPRECATED. It was renamed to `agentforce` in v2.5 (Phase 17).
  This file ships no patterns and is preserved for back-compat lookup only —
  some installed projects pinned the old pack name in `.claude/argo-packs.json`.

  See ../agentforce/patterns.md for the authoritative AGT-1..7 pattern set.
-->

# Einstein / Agentforce — DEPRECATED

This pack ships **no patterns**. It was renamed to [`agentforce`](../agentforce/) in v2.5 and the directory is retained only so that `pattern-pack remove einstein-agentforce` continues to work for projects that pinned the old name.

To migrate, run:

```text
/argo:pattern-pack remove einstein-agentforce
/argo:pattern-pack add agentforce
```

The new pack ships **AGT-1..7** (topic boundaries, sub-agent decomposition, guardrails, MCP-tool actions, FLS-aware grounding, memory & state, escalation paths) plus 8 quality-checklist additions.

> Subsequent v3.x or later releases may remove this directory entirely.
