#!/bin/bash
# sf-cli.sh — Thin wrapper around the Salesforce CLI (`sf`) used by org-aware skills.
#
# All org-touching wrappers route through `hooks/lib/security.sh` first:
#   - Prod aliases are hard-refused (sec_check_org)
#   - SOQL targets must be on the metadata allowlist (sec_check_soql)
#   - Anonymous Apex is refused unless explicitly enabled (sec_check_anon_apex)
#   - Data writes always require per-call consent (sec_check_data_write)
#
# This file is the authoritative shim for every org-touching operation; all
# org-aware skills route through these helpers (or `sf` directly behind the
# same security library).
#
# Public functions (return 0 on success; non-zero with a stderr message otherwise):
#   sf_cli_check                          — verify `sf` is installed
#   sf_cli_alias_exists  <alias>          — boolean: does the org alias resolve?
#   sf_cli_query         <soql> [alias]   — run SOQL (subject to metadata allowlist)
#   sf_cli_describe      <object> [alias] — describe an sObject (metadata)
#   sf_cli_org_display   [alias]          — print org info JSON (gated)
#   sf_cli_list_objects  [alias]          — list sObject API names (metadata)

# shellcheck shell=bash

if ! declare -F sec_check_org >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/security.sh"
fi

sf_cli_check() {
  if ! command -v sf >/dev/null 2>&1; then
    echo "[argo] Error: 'sf' (Salesforce CLI) not found. Install from https://developer.salesforce.com/tools/salesforcecli" >&2
    return 1
  fi
}

# Pure local lookup — no org contact. Safe to call without security check.
sf_cli_alias_exists() {
  local alias="$1"
  if [[ -z "$alias" ]]; then
    echo "[argo] Error: sf_cli_alias_exists requires an alias" >&2
    return 2
  fi
  sf_cli_check || return 1
  command -v jq >/dev/null 2>&1 || { echo "[argo] Error: jq required" >&2; return 1; }

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
    echo "[argo] Error: sf_cli_query requires SOQL" >&2
    return 2
  fi
  sf_cli_check || return 1

  # Security: org classification + SOQL allowlist.
  sec_check_soql "$soql" "$alias" || return $?

  local args=(--query "$soql" --json)
  [[ -n "$alias" ]] && args+=(--target-org "$alias")
  sf data query "${args[@]}"
}

sf_cli_describe() {
  local obj="$1"
  local alias="${2:-}"
  if [[ -z "$obj" ]]; then
    echo "[argo] Error: sf_cli_describe requires an sObject API name" >&2
    return 2
  fi
  sf_cli_check || return 1

  # describe is metadata only; just check the org.
  if [[ -n "$alias" ]]; then
    sec_check_org "$alias" || return $?
  fi

  local args=(--sobject "$obj" --json)
  [[ -n "$alias" ]] && args+=(--target-org "$alias")
  sf sobject describe "${args[@]}"
}

sf_cli_org_display() {
  local alias="${1:-}"
  sf_cli_check || return 1

  if [[ -n "$alias" ]]; then
    sec_check_org "$alias" || return $?
  fi

  local args=(--json)
  [[ -n "$alias" ]] && args+=(--target-org "$alias")
  sf org display "${args[@]}"
}

sf_cli_list_objects() {
  local alias="${1:-}"
  sf_cli_check || return 1

  if [[ -n "$alias" ]]; then
    sec_check_org "$alias" || return $?
  fi

  local args=(--json)
  [[ -n "$alias" ]] && args+=(--target-org "$alias")
  sf sobject list "${args[@]}"
}
