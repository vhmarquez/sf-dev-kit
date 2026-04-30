# Data Cloud (CDP) Pack

Patterns for **Salesforce Data Cloud** — the harmonized customer data platform: Data Streams, Data Lake Objects, Data Model Objects, identity resolution, calculated insights, segments, activations, and the SQL query surface for Apex and agents.

## When to use this pack

Install with `/sf-dev-kit:pattern-pack add data-cloud` if your project:
- Ingests data from multiple systems (CRM, web, POS, ERP) and needs unified individuals
- Computes derived metrics (LTV, churn risk, engagement scores) for activation
- Pushes audiences to Marketing Cloud, ad platforms, or custom webhooks via Data Cloud activations
- Grounds Agentforce agents in calculated insights (per-customer summaries the agent can reference)

Don't install for:
- Pure CRM workflows (standard objects + base patterns are enough)
- Real-time transactional systems (Data Cloud is analytical / scheduled-refresh)
- Marketing-only personalization without unified-customer semantics (Marketing Cloud Personalization is the simpler product)

## What's in the pack

- **DC-1: Data Streams and Data Lake Objects** — connectors, DLO schema, refresh cadence, primary keys
- **DC-2: Data Model Objects and Identity Resolution** — DMO mapping, match rules, Unified Individual semantics
- **DC-3: Calculated Insights and Segments** — scheduled SQL, segment-on-DMO discipline, refresh-cadence design
- **DC-4: Activation to External Systems** — incremental activation, Named Credentials, suppression lists, attribute mapping
- **DC-5: Querying Data Cloud from Apex / Agents** — SQL API (not SOQL), agent grounding, Data Space boundaries

Plus checklist items covering connector choice, identity match-key strength, segment-via-DMO discipline, suppression at activation, and Named Credential auth for the SQL API.

## What's not in the pack

- Marketing Cloud send / journey design — that's a Marketing Cloud concern
- Tableau CRM / Tableau Cloud analytics — separate analytical product
- Generative-AI grounding rules / Trust Layer — see the `agentforce` pack and `/sf-dev-kit:trust-layer-audit`

## Cross-references

- Related packs: `agentforce` (AGT-5: FLS-aware grounding can read Data Cloud insights), `change-data-capture` (CDC events flow into Data Cloud via the CRM connector)
- Base patterns: SF-15 (Named Credentials — for activation targets and SQL API), SF-9 (Wrapper / DTO Classes — for query result shapes)
- Specialist agents: `@data-architect` for DLO/DMO design, `@integration-architect` for connector/activation choices

## References

- [Data Cloud Developer Documentation](https://developer.salesforce.com/docs/atlas.en-us.c360a_api.meta/c360a_api/c360a_api_intro.htm)
- [Data Cloud SQL Reference](https://developer.salesforce.com/docs/atlas.en-us.c360a_api.meta/c360a_api/c360a_api_query_v2.htm)
- [Identity Resolution overview](https://help.salesforce.com/s/articleView?id=sf.c360_a_identity_resolution.htm)
