#!/bin/bash
# sf-cli.sh — Thin wrapper around the Salesforce CLI (`sf`) used by org-aware skills.
#
# Headless 360 / MCP note: for skills that benefit from agent-mediated calls, prefer
# the MCP toolsets via `${CLAUDE_PLUGIN_ROOT}/hooks/lib/mcp.sh` (`mcp_prefer` +
# `mcp_run <toolset> <tool>`). This file remains the always-works fallback path
# and is the authoritative shim used when `@salesforce/mcp` is absent or
# explicitly disabled (--no-mcp / SF_DEV_KIT_MCP_DISABLED=1).
#
# Public functions (all return 0 on success, non-zero with a message on stderr otherwise):
#   sf_cli_check                          — verify `sf` is installed
#   sf_cli_alias_exists  <alias>          — boolean: does the org alias resolve?
#   sf_cli_query         <soql> [alias]   — run SOQL, print JSON result on stdout
#   sf_cli_describe      <object> [alias] — describe an sObject, print JSON
#   sf_cli_org_display   [alias]          — print org info JSON
#   sf_cli_list_objects  [alias]          — print list of sObject API names

sf_cli_check() {
  if ! command -v sf >/dev/null 2>&1; then
    echo "[sf-dev-kit] Error: 'sf' (Salesforce CLI) not found. Install from https://developer.salesforce.com/tools/salesforcecli" >&2
    return 1
  fi
}

sf_cli_alias_exists() {
  local alias="$1"
  if [[ -z "$alias" ]]; then
    echo "[sf-dev-kit] Error: sf_cli_alias_exists requires an alias" >&2
    return 2
  fi
  sf_cli_check || return 1
  command -v jq >/dev/null 2>&1 || { echo "[sf-dev-kit] Error: jq required" >&2; return 1; }

  sf org list --json 2>/dev/null | jq -e --arg a "$alias" '
    .result as $r |
    [
      ($r.scratchOrgs    // [] | .[]?),
      ($r.nonScratchOrgs // [] | .[]?),
      ($r.devHubs        // [] | .[]?),
      ($r.sandboxes      // [] | .[]?),
      ($r.other          // [] | .[]?)
    ] | any(.alias == $a or .username == $a)
  ' >/dev/null
}

sf_cli_query() {
  local soql="$1"
  local alias="${2:-}"
  if [[ -z "$soql" ]]; then
    echo "[sf-dev-kit] Error: sf_cli_query requires SOQL" >&2
    return 2
  fi
  sf_cli_check || return 1
  local args=(--query "$soql" --json)
  [[ -n "$alias" ]] && args+=(--target-org "$alias")
  sf data query "${args[@]}"
}

sf_cli_describe() {
  local obj="$1"
  local alias="${2:-}"
  if [[ -z "$obj" ]]; then
    echo "[sf-dev-kit] Error: sf_cli_describe requires an sObject API name" >&2
    return 2
  fi
  sf_cli_check || return 1
  local args=(--sobject "$obj" --json)
  [[ -n "$alias" ]] && args+=(--target-org "$alias")
  sf sobject describe "${args[@]}"
}

sf_cli_org_display() {
  local alias="${1:-}"
  sf_cli_check || return 1
  local args=(--json)
  [[ -n "$alias" ]] && args+=(--target-org "$alias")
  sf org display "${args[@]}"
}

sf_cli_list_objects() {
  local alias="${1:-}"
  sf_cli_check || return 1
  local args=(--json)
  [[ -n "$alias" ]] && args+=(--target-org "$alias")
  sf sobject list "${args[@]}"
}
