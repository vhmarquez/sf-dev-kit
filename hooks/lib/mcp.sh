#!/bin/bash
# mcp.sh — Helpers for the Salesforce MCP server (`@salesforce/mcp`).
#
# This lib lets argo skills *prefer* the official Salesforce MCP toolsets
# (data, metadata, testing, lwc, code-analysis, devops, aura) when available,
# and fall back to direct `sf` CLI calls when not.
#
# All mcp_run invocations are gated by `hooks/lib/security.sh`:
#   - Prod-classified orgs are blocked unconditionally
#   - `data` toolset SOQL invocations check the metadata allowlist
#   - Write-shaped tool calls (deploy, create-record, run-anon-apex) check
#     per-toolset rules
#
# Public functions:
#   mcp_check                            — verify the MCP package is reachable; print version
#   mcp_available                        — boolean: is `@salesforce/mcp` resolvable via npx?
#   mcp_configured_toolsets   [env]      — print toolsets configured in sf-project.json
#   mcp_run                  <toolset> <tool-name> [json-args] [alias]
#                                         — invoke a single MCP tool; gated by security
#   mcp_list_tools            <toolset>  — list tools in a toolset
#   mcp_prefer                            — boolean: should we route through MCP?
#
# Requires: jq, npx (Node)

# shellcheck shell=bash

if ! declare -F sec_check_org >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/security.sh"
fi

mcp_check() {
  if ! command -v npx >/dev/null 2>&1; then
    echo "[argo/mcp] Error: npx (Node.js) not found. Install Node 20+." >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "[argo/mcp] Error: jq required." >&2
    return 1
  fi
  if ! npx -y @salesforce/mcp --version >/dev/null 2>&1; then
    echo "[argo/mcp] Salesforce MCP server not reachable. Install with /argo:mcp-setup." >&2
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
  if ! declare -F sf_config_get >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
  fi
  sf_config_get '.mcp.toolsets // [] | join(",")' "$env"
}

mcp_prefer() {
  if [[ -n "${ARGO_MCP_DISABLED:-}" ]]; then
    return 1
  fi
  mcp_available
}

# --- Security pre-flight for MCP calls ----------------------------------------

# Decide which security check applies to a (toolset, tool) pair.
# Returns 0 when allowed; non-zero when refused/consent-required (with stderr
# emitted by sec_*).
_mcp_security_check() {
  local toolset="$1"
  local tool="$2"
  local args_json="$3"
  local alias="$4"

  if sec_is_disabled; then
    return 0
  fi

  # Always validate the org first.
  if [[ -n "$alias" ]]; then
    sec_check_org "$alias" || return $?
  fi

  case "$toolset:$tool" in
    data:soql-query|data:query|data:soql)
      local soql
      soql=$(printf '%s' "$args_json" | jq -r '.soql // .query // .sql // empty' 2>/dev/null)
      if [[ -z "$soql" ]]; then
        _sec_emit "refused" "MCP_SOQL_NOT_PARSEABLE" "soql" "" "$alias" \
          "MCP data tool invocation didn't include a parseable SOQL string in args."
        return 78
      fi
      sec_check_soql "$soql" "$alias" || return $?
      ;;
    data:create-record|data:update-record|data:delete-record|data:upsert|data:bulk*)
      sec_check_data_write "$alias" "data-write" || return $?
      ;;
    testing:run-anon-apex|metadata:run-anon-apex|*:run-anon-apex)
      sec_check_anon_apex "$alias" || return $?
      ;;
    testing:run-agent-test|testing:agent-eval|*:agent-test*)
      sec_check_data_write "$alias" "agent-eval" || return $?
      ;;
    *)
      # Default: org check is enough. Toolsets like metadata/lwc/code-analysis
      # operate on metadata or local sources.
      ;;
  esac
}

# Invoke a single tool from a single toolset.
# Args:  <toolset> <tool> [json-args] [alias]
# Stdout: JSON tool result
# Returns: 0 on success; 77 (consent required), 78 (refused), or tool exit code
mcp_run() {
  local toolset="$1"
  local tool="$2"
  local args_json="${3:-{\}}"
  local alias="${4:-}"

  if [[ -z "$toolset" ]] || [[ -z "$tool" ]]; then
    echo "[argo/mcp] Usage: mcp_run <toolset> <tool> [json-args] [alias]" >&2
    return 2
  fi

  # If alias not passed, sniff from JSON args (`org` field convention) for
  # security gating.
  if [[ -z "$alias" ]]; then
    alias=$(printf '%s' "$args_json" | jq -r '.org // .targetOrg // empty' 2>/dev/null || echo "")
  fi

  _mcp_security_check "$toolset" "$tool" "$args_json" "$alias" || return $?

  mcp_check >/dev/null || return 1

  npx -y @salesforce/mcp \
    --toolsets "$toolset" \
    --invoke "$tool" \
    --args "$args_json" \
    --json 2>/dev/null
}

# Convenience: list available tools in a toolset (for skills that want to
# enumerate what they can call). No org contact, no security check needed.
mcp_list_tools() {
  local toolset="$1"
  if [[ -z "$toolset" ]]; then
    echo "[argo/mcp] Usage: mcp_list_tools <toolset>" >&2
    return 2
  fi
  mcp_check >/dev/null || return 1
  npx -y @salesforce/mcp --toolsets "$toolset" --list-tools --json 2>/dev/null
}
