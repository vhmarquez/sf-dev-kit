#!/bin/bash
# security-guard.sh — PreToolUse hook on Bash. Defense-in-depth wrapper around
# raw `sf` CLI commands that bypass the library helpers in hooks/lib/sf-cli.sh.
#
# Purpose: even if a skill (or hand-written Bash) calls `sf` directly, the
# four invariants from hooks/lib/security.sh are enforced before the command
# reaches the shell. The library is the primary mechanism; this hook closes
# the bypass.
#
# Wire protocol:
#   - Allowed       → exit 0 (silent)
#   - Refused       → exit 2 (PreToolUse contract: blocks the tool call) + JSON event on stderr
#   - Consent required → exit 2 + JSON event with event="consent_required"
#                        The assistant should present the event, get user OK,
#                        and re-invoke with ARGO_CONSENT_GRANTED=once.
#
# Disable per-session for testing: ARGO_SECURITY_GUARD=0 (NOT recommended;
# this defeats the safety net — the library still enforces, but raw `sf` calls
# stop being audited).

set -u

if [[ "${ARGO_SECURITY_GUARD:-1}" == "0" ]]; then
  exit 0
fi

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  # Without jq we can't parse — fail open, but surface a warning. The library
  # itself also requires jq, so this state is degenerate anyway.
  echo "[argo/security-guard] jq not found — guard disabled for this call" >&2
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$COMMAND" ]] && exit 0

# Quickly bail when the command has no `sf` CLI invocation. Word-boundary match;
# avoid false positives on filenames that contain "sf".
if ! grep -qE '(^|[[:space:];|&(])sf([[:space:]]|$)' <<< "$COMMAND"; then
  exit 0
fi

# Source the security library + config helpers.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -z "$PLUGIN_ROOT" ]] || [[ ! -f "${PLUGIN_ROOT}/hooks/lib/security.sh" ]]; then
  # Library missing — the library is the source of truth for the metadata
  # allowlist. Without it we can't make a confident decision; fail closed for
  # known-dangerous patterns, fail open otherwise.
  if grep -qE '\bsf[[:space:]]+(data[[:space:]]+(query|create|update|delete|import|export)|apex[[:space:]]+run)\b' <<< "$COMMAND"; then
    echo "[argo/security-guard] CLAUDE_PLUGIN_ROOT not set; refusing potentially-dangerous sf command" >&2
    exit 2
  fi
  exit 0
fi

# shellcheck source=/dev/null
source "${PLUGIN_ROOT}/hooks/lib/security.sh"

# --- Extract the alias (if any) -----------------------------------------------

# Capture --target-org / -o <alias>; otherwise empty (let library's
# defaultTargetOrg classification handle it later).
extract_target_org() {
  local cmd="$1"
  printf '%s' "$cmd" | grep -oE -- '(--target-org|-o)[[:space:]]+[A-Za-z0-9._@+-]+' | head -1 | awk '{print $2}'
}

ALIAS=$(extract_target_org "$COMMAND")
if [[ -z "$ALIAS" ]]; then
  ALIAS=$(sf_config_get '.platform.defaultTargetOrg // empty' "${SF_ENV:-}" 2>/dev/null || echo "")
fi

# --- Identify the sf subcommand -----------------------------------------------

# We only inspect the first `sf <verb> <noun>` we find. Compound commands with
# multiple `sf` calls are rare; the library still gates each individual call,
# and the hook runs on every Bash invocation.
SF_INVOKE=$(printf '%s' "$COMMAND" | grep -oE '\bsf[[:space:]]+[a-z]+([[:space:]]+[a-z-]+)?' | head -1 | tr -s ' ' || true)

# Verb-tail mapping → category
case "$SF_INVOKE" in
  "sf org list"|"sf alias list")
    # Local-only — no org contact.
    exit 0
    ;;
  "sf org display"|"sf org open")
    # Connection metadata read; gate by org classification.
    if [[ -n "$ALIAS" ]]; then
      sec_check_org "$ALIAS"; rc=$?
      [[ $rc -ne 0 ]] && exit 2
    fi
    exit 0
    ;;
  "sf project deploy"|"sf project retrieve"|"sf metadata deploy"|"sf metadata retrieve"|"sf source push"|"sf source pull")
    # Metadata read/write — allowed for non-prod.
    if [[ -n "$ALIAS" ]]; then
      sec_check_org "$ALIAS"; rc=$?
      [[ $rc -ne 0 ]] && exit 2
    fi
    exit 0
    ;;
  "sf sobject describe"|"sf sobject list"|"sf schema generate")
    # Pure metadata.
    if [[ -n "$ALIAS" ]]; then
      sec_check_org "$ALIAS"; rc=$?
      [[ $rc -ne 0 ]] && exit 2
    fi
    exit 0
    ;;
  "sf data query")
    # Extract --query "<soql>" or --query <soql> (single token).
    SOQL=$(printf '%s' "$COMMAND" | grep -oE -- '--query[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:]]+)' | head -1 | sed -E 's/^--query[[:space:]]+//; s/^["'\'']//; s/["'\'']$//')
    if [[ -z "$SOQL" ]]; then
      _sec_emit "refused" "SOQL_NOT_PARSEABLE" "soql" "" "$ALIAS" \
        "Could not extract --query argument from sf data query command. Quote the SOQL with single or double quotes."
      exit 2
    fi
    sec_check_soql "$SOQL" "$ALIAS"; rc=$?
    [[ $rc -ne 0 ]] && exit 2
    exit 0
    ;;
  "sf data create-record"|"sf data update-record"|"sf data delete-record"|"sf data upsert"|"sf data import"|"sf data export"|"sf data tree"|"sf data create-bulk")
    sec_check_data_write "$ALIAS" "data-write"; rc=$?
    [[ $rc -ne 0 ]] && exit 2
    exit 0
    ;;
  "sf apex run")
    # Disambiguate `sf apex run` (anon Apex) from `sf apex run test` (test runs).
    if grep -qE '\bsf[[:space:]]+apex[[:space:]]+run[[:space:]]+test\b' <<< "$COMMAND"; then
      # Test runs against allowed orgs are fine — the test code is metadata.
      if [[ -n "$ALIAS" ]]; then
        sec_check_org "$ALIAS"; rc=$?
        [[ $rc -ne 0 ]] && exit 2
      fi
      exit 0
    fi
    sec_check_anon_apex "$ALIAS"; rc=$?
    [[ $rc -ne 0 ]] && exit 2
    exit 0
    ;;
  "sf agent run"|"sf agent test"|"sf agent generate")
    # Agent test runs hit AgentSessionTrace etc. — gated as data.
    case "$SF_INVOKE" in
      "sf agent test"|"sf agent run")
        sec_check_data_write "$ALIAS" "agent-eval"; rc=$?
        [[ $rc -ne 0 ]] && exit 2
        ;;
      *)
        if [[ -n "$ALIAS" ]]; then
          sec_check_org "$ALIAS"; rc=$?
          [[ $rc -ne 0 ]] && exit 2
        fi
        ;;
    esac
    exit 0
    ;;
  "sf force"|"")
    # Legacy `sf force:*` colon-separated form, or no recognizable subcommand.
    # Check if it looks data-shaped; otherwise allow with org check.
    if grep -qE '\bsf[[:space:]]+force:data:|\bsf[[:space:]]+force:apex:execute' <<< "$COMMAND"; then
      sec_check_data_write "$ALIAS" "data-write"; rc=$?
      [[ $rc -ne 0 ]] && exit 2
    elif [[ -n "$ALIAS" ]]; then
      sec_check_org "$ALIAS"; rc=$?
      [[ $rc -ne 0 ]] && exit 2
    fi
    exit 0
    ;;
  *)
    # Unrecognized subcommand. Be conservative: gate by org classification only.
    if [[ -n "$ALIAS" ]]; then
      sec_check_org "$ALIAS"; rc=$?
      [[ $rc -ne 0 ]] && exit 2
    fi
    exit 0
    ;;
esac
