---
name: mcp-tool-vs-rest
description: Decide whether to expose work as an MCP tool, an Apex REST endpoint, or a Platform Event. Headless 360 made MCP tools a peer integration pattern; this skill maps the choice space.
data-access: metadata-only
---

You are picking an integration pattern for exposing project work to other systems (or other agents). Three primary options post-Headless-360: **MCP tool**, **Apex REST service** (SF-16), **Platform Event** (PE pack). Each fits a different shape.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/mcp.sh"
```

## Input

`$ARGUMENTS`:
- (empty) — interactive
- `<one-line description>` — concrete operation
- `--non-interactive answers="..."` — scripted

## Decision questions

1. **Caller — agent (LLM-driven), human/UI app, or another system?**
2. **Synchronous request/response, or fire-and-forget event?**
3. **Schema knowledge — does the caller need a typed input/output schema, or can it adapt?**
4. **Authentication — caller has Salesforce credentials, or should auth be bridged?**
5. **Volume — single calls (per user action) or high-throughput?**
6. **Discoverability — should the tool be findable in the Agent Registry, AppExchange, or just documented?**

## Decision tree

```
Caller is an agent (LLM-driven)
  → MCP Tool
    Bridged via /sf-dev-kit:mcp-bridge from an Apex REST class (SF-16)
    Schema-typed input/output, registered in Agent Registry (AGT-4)

Caller is a third-party system, sync request/response
  → Apex REST Service (SF-16)
    Pair with Connected App + JWT bearer for auth
    Document in OpenAPI spec for portal listings

Caller is internal Salesforce (e.g., another org, MuleSoft)
  → Apex REST OR Platform Event (depending on event-vs-RPC shape)
    REST for "give me X right now"
    PE for "tell everyone X happened"

Fire-and-forget broadcast to many subscribers
  → Platform Event (platform-events pack)
    Standard or High-Volume per PE-4
    Subscribers are decoupled (Apex trigger, LWC empApi, external Pub/Sub API)

Bidirectional record sync (CDC)
  → Change Data Capture (change-data-capture pack — CDC-1..5)
    Auto-emitted on persistence; replay window 3 days

Read-only external data (reverse direction — pulling INTO Salesforce)
  → External Object via Salesforce Connect (external-objects pack)
    OData-based; no replication

Bulk import from external
  → Bulk API 2.0 (project-external integration; not a SF-N pattern)
```

## When to combine

- **MCP Tool wrapping an Apex REST endpoint** — most common. The Apex REST is the source of truth (versioned, deployable); the MCP tool is the agent-facing facade with type schema. `/sf-dev-kit:mcp-bridge` does this in one step
- **REST + PE** — REST for the synchronous "create order" call; PE for the asynchronous "order created" broadcast that other systems pick up
- **MCP Tool + PE subscription** — an agent invokes the tool, which fires a PE; a separate Apex subscriber handles the side effects

## Output

```
# Choice: <one-line description>

## Answers
- Caller:           Agentforce agent (order_helper)
- Sync/async:       sync (user expects an immediate answer in chat)
- Schema:           strongly typed (order id in, order details out)
- Auth:             bridged (the user is in Slack; the agent runs as the Salesforce user mapped via Slack OAuth)
- Volume:           ~10 calls / minute peak; not high-throughput
- Discoverability:  yes — should appear in the Agent Registry so other agents can use it

## Recommendation: **MCP Tool wrapping an Apex REST class**

### Why
- The agent caller pattern fits MCP's design exactly: typed input/output schemas, discoverable, schema-validated outputs
- Volume is low — synchronous REST under MCP is fine
- Reuse: an Apex REST class (SF-16) is the source of truth and can also be called from other systems; the MCP bridge is the agent-facing facade
- Auth is handled by the platform — the agent's session is the Salesforce session; MCP routes through it

### Implementation outline
- @apex-dev: implement OrderRestService (SF-16) with @HttpGet returning a typed Response envelope
- /sf-dev-kit:mcp-bridge OrderRestService — generates mcp/bridges/order_get.json
- @apex-dev: implement OrderRestServiceTest with HttpCalloutMock-style coverage
- @agent-dev: bind `order_get` to the lookup_order topic in the agent spec (AGT-4)
- /sf-dev-kit:mcp-bridge --register — registers the tool in the Agent Registry so other agents can discover it

### Patterns referenced
- SF-16 (Apex REST service)
- AGT-4 (Action via MCP Tool)
- SF-15 (only if the REST service itself makes external callouts)

### Alternatives considered
- **Apex REST only** (no MCP bridge): would work for non-agent callers, but the agent would need to know REST endpoints, auth, and Connect API. MCP abstracts that
- **Platform Event** (publish "order_lookup_requested" + subscribe later): wrong shape — the agent needs an immediate response, not a broadcast
- **Direct Apex call from the agent**: bypasses MCP's schema validation and discoverability. Don't
```

## Rules

- **Agents → MCP Tool, almost always.** Even when the underlying work is a single Apex method, the bridge gives schema validation, discoverability, and a stable interface
- **One source of truth.** The Apex REST is the implementation; the MCP bridge is a facade. Don't duplicate logic in both
- **Don't expose write operations as MCP tools without explicit confirmation patterns.** AGT-4 + AGT-3: agent-side confirmation; the underlying REST verb is `@HttpPost` only when explicitly requested
- **Document the OpenAPI surface for human callers.** Even if the primary caller is an agent, third parties will find the REST and want a spec

## Consumers

- `@integration-architect` invokes this for any new external-facing operation
- `@agent-dev` accepts the recommendation when defining new agent actions
- `/sf-dev-kit:adr` captures the decision
