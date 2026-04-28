---
name: mcp-setup
description: Install and configure the Salesforce MCP server (`@salesforce/mcp`) for this project. Persists chosen toolsets to `sf-project.json` `mcp.toolsets`, scopes per-environment, and writes a `.mcp.json` config Claude Code (and other MCP clients) can pick up.
---

You are setting up the **Salesforce MCP server** announced in Headless 360. Once installed, downstream sf-dev-kit skills (`/org-explore`, `/deploy`, `/test-coverage`, `/security-scan`, `/agent-test`, etc.) prefer the MCP toolsets when available and fall back to direct `sf` CLI when not. Scoping toolsets matters: every tool you expose costs LLM context window — start narrow.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/mcp.sh"
PROJECT_DIR="${CLAUDE_PROJECT_DIR}"
```

## Available Toolsets (per `@salesforce/mcp` v1)

| Toolset | What it gives the agent |
|---------|--------------------------|
| `metadata` | Deploy/retrieve metadata between DX projects and orgs |
| `data` | Execute SOQL queries against live orgs |
| `testing` | Run Apex tests, agent evaluation tests |
| `lwc` | Create LWC components, generate Jest tests, accessibility guidance |
| `code-analysis` | Static analysis via Salesforce Code Analyzer |
| `devops` | CI/CD pipeline access through DevOps Center MCP |
| `aura` | Migration blueprints, LWC transition guidance |

Recommended starter sets:
- **Dev** (interactive): `metadata, data, testing, lwc, code-analysis`
- **CI** (build/deploy): `metadata, testing, devops, code-analysis`
- **Read-only review** (`/code-review`, `@security-reviewer`): `data, code-analysis`
- **Agent dev**: `metadata, testing, data` — `testing` includes agent eval tests

## Input

`$ARGUMENTS`:
- (empty) — interactive walkthrough
- `--toolsets <list>` — comma-separated toolsets to enable (skips the prompt)
- `--env <name>` — write the config under the env override file instead of base
- `--profile dev|ci|review|agent` — apply a recommended toolset bundle (above)
- `--ci` — non-interactive, JSON output
- `--check` — verify install only, no changes

## Steps

### 1. Verify prerequisites

```bash
command -v node >/dev/null || { echo "[mcp-setup] Node.js not found"; exit 2; }
node --version | grep -E 'v(2[0-9]|[3-9][0-9])' >/dev/null || echo "[mcp-setup] Warning: Node 20+ recommended"
mcp_check && echo "[mcp-setup] @salesforce/mcp resolvable via npx" || echo "[mcp-setup] @salesforce/mcp NOT yet resolvable"
```

### 2. Pick toolsets

If `--profile` was passed, use the profile mapping above.
If `--toolsets` was passed, use that.
Otherwise, walk the user through:

```
Available toolsets:
  [x] metadata        Deploy/retrieve metadata
  [x] data            Run SOQL queries against live orgs
  [x] testing         Run Apex tests + agent evaluation tests
  [x] lwc             Scaffold LWC components and Jest tests
  [x] code-analysis   Salesforce Code Analyzer (security, quality)
  [ ] devops          DevOps Center MCP (CI/CD)
  [ ] aura            Aura → LWC migration blueprints

Type [+name] to enable, [-name] to disable, or 'next' to accept the marked set.
```

Confirm the chosen set explicitly before writing.

### 3. Persist to `sf-project.json` (or env override)

Add (or update) the `mcp` section:
```json
{
  "mcp": {
    "toolsets": ["metadata", "data", "testing", "lwc", "code-analysis"],
    "allowNonGaTools": false,
    "scope": "org-or-current"
  }
}
```

If `--env <name>` was passed, write to `.claude/sf-project.<name>.json` instead — it deep-merges over the base. Common pattern: `prod` env override pares down to `data, testing` only (no metadata or devops in prod-from-dev contexts).

### 4. Write `.mcp.json` for Claude Code / MCP clients

If `.mcp.json` doesn't exist in the project, scaffold it:

```json
{
  "mcpServers": {
    "salesforce": {
      "command": "npx",
      "args": ["-y", "@salesforce/mcp", "--orgs", "DEFAULT_ORG_PLACEHOLDER", "--toolsets", "metadata,data,testing,lwc,code-analysis"]
    }
  }
}
```

Substitute `DEFAULT_ORG_PLACEHOLDER` with `platform.defaultTargetOrg` from config. If a `.mcp.json` already exists, merge the `salesforce` server entry into it without touching other servers.

### 5. Smoke-test the install

```bash
mcp_run testing list-tools '{}' >/dev/null 2>&1 && echo "[mcp-setup] testing toolset reachable"
mcp_run data list-tools '{}' >/dev/null 2>&1 && echo "[mcp-setup] data toolset reachable"
```

If the smoke test fails, surface the underlying error (auth, version, network) clearly and offer next steps.

### 6. Report

Default Markdown:
```
# MCP Setup: <project.name>

✅ @salesforce/mcp version: 1.4.2
✅ Toolsets configured (base): metadata, data, testing, lwc, code-analysis
✅ Toolsets configured (env=prod): data, testing
✅ .mcp.json updated (merged with 1 existing server entry)
✅ Smoke test: testing + data + metadata reachable

## Recommended next steps
- Run /sf-dev-kit:org-explore (it now prefers the MCP `data` toolset; pass --no-mcp to use the legacy CLI path)
- Run /sf-dev-kit:agent-discover to inventory existing AgentDefinitions
- Run /sf-dev-kit:mcp-bridge if you want to expose a project Apex REST endpoint as an MCP tool
- For CI: regenerate the env override with `/sf-dev-kit:mcp-setup --env ci --profile ci`
```

CI mode JSON: `{"installed": true, "version": "1.4.2", "toolsets": [...], "envOverrides": {"prod": [...]}}`.

### 7. Exit codes
- 0 — install + config persisted
- 1 — `@salesforce/mcp` not resolvable (offer install instructions)
- 2 — config write error / invalid toolset name

## Rules

- **Start narrow.** Every enabled tool consumes LLM context. Default to the `dev` profile for interactive work; CI uses a smaller set
- **Per-env scoping is normal.** Production runs from CI rarely need `lwc` or `aura`. Trim with env overrides
- **Don't enable `--allow-non-ga-tools` in CI or production.** It's a dev-only flag for pre-release experimentation
- **`.mcp.json` lives in the user's project** — it's how Claude Code and other MCP clients discover the server. Sensitive — don't commit if it contains secrets (it shouldn't, but check)
- **Don't auto-update the version.** Pin in `package.json` (or rely on `npx -y` for the latest tag); version bumps can change tool surfaces
