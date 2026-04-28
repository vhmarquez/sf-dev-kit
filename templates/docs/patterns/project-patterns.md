# Project-Specific Code Patterns

Patterns and shared components specific to this codebase. Read alongside `docs/patterns/salesforce-patterns.md` (generic Salesforce techniques) and `docs/project-context.md` (object model, channels, glossary).

---

_TODO_: Add project-specific patterns here as they emerge. Common categories:

- **LMS channel subscriptions** — list each channel the project uses and any project-specific behavior
- **Reusable shared LWCs** — components other LWCs should reuse rather than recreate
- **Logger / error-handling utilities** — project-specific error logging conventions
- **Trigger framework details** — names of dispatcher and interface classes if the project uses one
- **Async-guard patterns** — project-specific Queueable / future / batch conventions

If a pattern is fully captured by the generic Salesforce-platform pattern in `docs/patterns/salesforce-patterns.md`, do not duplicate it here — only add what's project-specific.
