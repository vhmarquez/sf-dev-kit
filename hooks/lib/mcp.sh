#!/bin/bash
# mcp.sh — Helpers for the Salesforce MCP server (`@salesforce/mcp`).
#
# This lib lets sf-dev-kit skills *prefer* the official Salesforce MCP toolsets
# (data, metadata, testing, lwc, code-analysis, devops, aura) when available,
# and fall back to direct `sf` CLI calls when not.
#
# Public functions:
#   mcp_check                          — verify the MCP package is reachable; print version
#   mcp_available                      — boolean: is `@salesforce/mcp` resolvable via npx?
#   mcp_configured_toolsets   [env]    — print the toolsets configured in sf-project.json (mcp.toolsets)
#   mcp_run                  <toolset> <tool-name> [json-args]
#                                       — invoke a single MCP tool; prints JSON result on stdout
#   mcp_prefer                         — boolean: should we route through MCP for this run?
#                                         (true if mcp_available AND --mcp not explicitly disabled)
#
# Requires: jq, npx (Node)

mcp_check() {
  if ! command -v npx >/dev/null 2>&1; then
    echo "[sf-dev-kit/mcp] Error: npx (Node.js) not found. Install Node 20+." >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "[sf-dev-kit/mcp] Error: jq required." >&2
    return 1
  fi
  if ! npx -y @salesforce/mcp --version >/dev/null 2>&1; then
    echo "[sf-dev-kit/mcp] Salesforce MCP server not reachable. Install with /sf-dev-kit:mcp-setup." >&2
    return 1
  fi
  npx -y @salesforce/mcp --version 2>/dev/null
}

mcp_available() {
  command -v npx >/dev/null 2>&1 \
    && command -v jq  >/dev/null 2>&1 \
    && npx -y @salesforce/mcp --version >/dev/null 2>&1
}

mcp_configured_toolsets() {
  local env="${1:-}"
  # Source the config helper if not already sourced (idempotent guard).
  if ! declare -F sf_config_get >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
  fi
  sf_config_get '.mcp.toolsets // [] | join(",")' "$env"
}

mcp_prefer() {
  # Honor an explicit override env var if the caller set one.
  if [[ -n "${SF_DEV_KIT_MCP_DISABLED:-}" ]]; then
    return 1
  fi
  mcp_available
}

# Invoke a single tool from a single toolset.
# Args:  <toolset> <tool> [json-args]
# Stdout: JSON tool result
# Returns: tool exit code
mcp_run() {
  local toolset="$1"
  local tool="$2"
  local args_json="${3:-{\}}"

  if [[ -z "$toolset" ]] || [[ -z "$tool" ]]; then
    echo "[sf-dev-kit/mcp] Usage: mcp_run <toolset> <tool> [json-args]" >&2
    return 2
  fi
  mcp_check >/dev/null || return 1

  # @salesforce/mcp invocation contract: each toolset is a JSON-RPC server; we
  # frame a single invocation as a JSON-RPC request and pipe to the appropriate
  # transport. The `--invoke` shape is the supported one-shot mode.
  npx -y @salesforce/mcp \
    --toolsets "$toolset" \
    --invoke "$tool" \
    --args "$args_json" \
    --json 2>/dev/null
}

# Convenience: list available tools in a toolset (for skills that want to
# enumerate what they can call).
mcp_list_tools() {
  local toolset="$1"
  if [[ -z "$toolset" ]]; then
    echo "[sf-dev-kit/mcp] Usage: mcp_list_tools <toolset>" >&2
    return 2
  fi
  mcp_check >/dev/null || return 1
  npx -y @salesforce/mcp --toolsets "$toolset" --list-tools --json 2>/dev/null
}
