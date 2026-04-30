---
name: mcp-bridge
description: Wrap an existing Apex REST endpoint (SF-16) as an MCP tool exposed to agents. Generates a bridge config + tool schema, registers in the Agent Registry, and (optionally) emits a sample agent prompt that uses the new tool.
data-access: metadata-only
---

You are exposing project-owned Apex REST services to agents as **first-class MCP tools**. This closes the loop between SF-16 (Apex REST Service) and the agent ecosystem: anything the team already exposes via `/services/apexrest/*` becomes invokable from an agent's tool palette.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/mcp.sh"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
```

## Input

`$ARGUMENTS`:
- `<ApexClassName>` — wrap this Apex class (must be `@RestResource`); skill discovers urlMapping + verbs
- `<ApexClassName>:<verb>` — wrap a single verb (`OrderRestService:GET`)
- `--tool-name <name>` — override default tool name (default: derived from class + verb, e.g., `order_get`)
- `--description <text>` — short description for the tool palette (default: derived from ApexDoc)
- `--register` — also register with the org's Agent Registry so existing agents can discover it
- `--env <name>` — for the org used during registration
- `--ci` — non-interactive

## Steps

### 1. Locate and validate the source

```bash
[[ -f "${APEX_SRC}/${CLASS}.cls" ]] || { echo "[mcp-bridge] ${CLASS}.cls not found in ${APEX_SRC}" >&2; exit 2; }

# Verify @RestResource and capture urlMapping
grep -E '@RestResource\s*\(\s*urlMapping\s*=\s*'\''[^'\'']+'\'' \s*\)' "${APEX_SRC}/${CLASS}.cls" \
  || { echo "[mcp-bridge] ${CLASS} is not annotated with @RestResource — pattern SF-16 first" >&2; exit 2; }
```

### 2. Discover verbs

Parse the source for `@HttpGet`, `@HttpPost`, `@HttpPut`, `@HttpDelete`, `@HttpPatch`. For each, capture:
- The method name
- The parameter list (becomes the MCP tool's input schema)
- The return type (becomes the output schema)
- ApexDoc summary if present (becomes the description)

### 3. Build the MCP tool definition

For each verb, emit a JSON tool spec following the MCP tool schema:

```json
{
  "name": "order_get",
  "description": "Fetch an order by id from the Salesforce backend.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "orderId": {"type": "string", "description": "Salesforce 18-char Id of the Order__c"}
    },
    "required": ["orderId"]
  },
  "outputSchema": {
    "type": "object",
    "properties": {
      "id":     {"type": "string"},
      "name":   {"type": "string"},
      "status": {"type": "string"},
      "total":  {"type": "number"}
    }
  },
  "binding": {
    "type": "salesforce-apex-rest",
    "class": "OrderRestService",
    "verb": "GET",
    "urlMapping": "/orders/*",
    "namedCredential": null
  }
}
```

The `binding` block tells the bridge runtime how to dispatch the call. The default execution path is via the `metadata` MCP toolset, which can invoke Apex REST against the org without a logged-in user (Connect REST uses Connected App / JWT auth — see `/argo:mcp-setup` for setup).

### 4. Persist the bridge spec

Write to `mcp/bridges/<tool-name>.json` (project-relative). Multiple bridges accumulate in this directory.

If a `.mcp.json` exists, append a `salesforce-bridges` server entry that points at the directory:

```json
{
  "mcpServers": {
    "salesforce-bridges": {
      "command": "npx",
      "args": ["-y", "@salesforce/mcp-bridge-runtime", "--config", "mcp/bridges/"]
    }
  }
}
```

(`@salesforce/mcp-bridge-runtime` is the runtime that loads bridge specs from the directory and serves them as a unified MCP server. Versioned and pinned alongside `@salesforce/mcp`.)

### 5. (Optional) Register with Agent Registry

If `--register`:
```bash
mcp_run devops register-agent-tool \
  '{"name":"order_get","specPath":"mcp/bridges/order_get.json","org":"'"$ORG"'"}'
```

This makes the tool discoverable by any agent that reads from the Agent Registry in this org.

### 6. Emit a sample agent prompt

Generate a small example showing how an agent invokes the new tool:

```yaml
# specs/example-uses-order_get.yaml (illustrative — not committed)
name: order-lookup-helper
role: Look up orders by id when asked
tools:
  - order_get        # ← the tool you just bridged
prompt: |
  When the user asks about an order, call `order_get` with the orderId
  they provided. Format the response as a short summary.
```

### 7. Output

Default Markdown:
```
# MCP Bridge: OrderRestService

Wrapped 2 of 2 verbs:
- order_get   → @HttpGet  /orders/*
- order_post  → @HttpPost /orders/*

Spec files:
- mcp/bridges/order_get.json
- mcp/bridges/order_post.json

.mcp.json updated to include `salesforce-bridges` server.

✅ Registered with Agent Registry: 2 tools
   Org: DevVM
   Visibility: All agents in the org can now invoke `order_get` and `order_post`

Suggested next steps:
- Test from an agent: ask Claude (or the org's agents) to "look up order O-1234"
- Add the new tool to your project's @agent-dev system prompt by listing it under `Available tools`
- Run /argo:agent-discover to confirm it shows up in the registry inventory
```

CI mode JSON: `{"className": "OrderRestService", "tools": [{"name": "order_get", "verb": "GET"}, ...], "registered": true}`.

### 8. Exit codes
- 0 — bridge spec(s) written (and optionally registered)
- 1 — verb discovery returned 0 (class is `@RestResource` but has no `@HttpX` methods)
- 2 — class not found / not `@RestResource` / write error

## Rules

- **Project-owned tools.** Bridges expose *your* Apex; never wrap something you don't control (managed-package classes, standard objects' built-in REST endpoints) — those are already on `@salesforce/mcp`'s data toolset
- **Inputs from ApexDoc.** A class with rich ApexDoc produces better MCP tool descriptions. Recommend SF-12 (Apex Inline Docs) before bridging
- **Don't expose write verbs by default.** `@HttpPost`/`@HttpPut`/`@HttpDelete` are wrapped only when explicitly requested via the `<Class>:<verb>` form (or by passing `--include-writes` in batch mode)
- **Registration is org-scoped.** A bridge registered in dev does not propagate to prod — re-run with the `--env prod` override to register in prod
- **Test the bridge** through the MCP Inspector or an agent before relying on it: `npx @modelcontextprotocol/inspector npx -y @salesforce/mcp-bridge-runtime --config mcp/bridges/`

## Consumers

- Agents in this org pick up bridge tools through their tool-palette discovery
- `@agent-dev` and `@architect` reference bridge tools when planning new agents
- `/argo:agent-discover` lists registered bridges per org
