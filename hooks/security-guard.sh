#!/bin/bash
# security-guard.sh — PreToolUse hook on Bash. Defense-in-depth wrapper around
# raw `sf` CLI commands that bypass the library helpers in hooks/lib/sf-cli.sh.
#
# Purpose: even if a skill (or hand-written Bash) calls `sf` directly, the
# four invariants from hooks/lib/security.sh are enforced before the command
# reaches the shell. The library is the primary mechanism; this hook closes
# the bypass.
#
# Coverage model (be honest about it):
#   - The command string is split on shell separators (; && || | & newline)
#     and EVERY segment that invokes `sf` is gated independently. Prefixing a
#     benign `sf` verb no longer bypasses gating of a later segment.
#   - `sf` is detected even when path-qualified (/usr/local/bin/sf) or quoted
#     ('sf'). It is NOT detected through shell indirection (var expansion `$X`,
#     `eval`, aliases). A regex guard fundamentally cannot catch those — the
#     library remains the primary enforcement layer. See
#     docs/security-model.md "Known limitations".
#
# Wire protocol:
#   - Allowed       → exit 0 (silent)
#   - Refused       → exit 2 (PreToolUse contract: blocks the tool call) + JSON event on stderr
#   - Consent required → exit 2 + JSON event with event="consent_required"
#                        The assistant should present the event, get user OK,
#                        and re-invoke with `ARGO_CONSENT_GRANTED=once sf ...`.
#                        This hook parses that inline assignment out of the
#                        command and honors it for a single call.
#
# Disable per-session for testing: ARGO_SECURITY_GUARD=0 (NOT recommended;
# this defeats the safety net — the library still enforces, but raw `sf` calls
# stop being audited).

set -u

if [[ "${ARGO_SECURITY_GUARD:-1}" == "0" ]]; then
  exit 0
fi

INPUT=$(cat)

# Patterns that touch org data / run code. Used by the fail-closed fallbacks
# (when we cannot fully parse) and is intentionally broad.
_looks_dangerous() {
  grep -qE '\bsf[[:space:]]+(data[[:space:]]+(query|create-record|update-record|delete-record|upsert|import|export|tree|create-bulk|update-bulk)|apex[[:space:]]+run|agent[[:space:]]+(run|test))\b|\bsf[[:space:]]+force:(data|apex)' <<< "$1"
}

if ! command -v jq >/dev/null 2>&1; then
  # Without jq we can't parse the tool_input JSON. Fail CLOSED for dangerous
  # patterns (grep the raw payload), fail open otherwise. The library also
  # requires jq, so this state is degenerate — but the guard must not silently
  # wave through a prod-targeted data query just because jq is absent.
  if _looks_dangerous "$INPUT"; then
    printf '%s\n' '{"event":"refused","reason":"JQ_MISSING_FAILCLOSED","skill":"unknown","action":"any","target":"","org":"","message":"jq not found; the security guard cannot parse the command and refuses potentially-dangerous sf invocations. Install jq."}' >&2
    exit 2
  fi
  echo "[argo/security-guard] jq not found — guard degraded for this call" >&2
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$COMMAND" ]] && exit 0

# Honor the documented single-use consent token when passed inline on the
# command (the re-invoke form `ARGO_CONSENT_GRANTED=once sf ...`). A command
# prefix only enters the *child* process's environment, never this hook's, so
# we must lift it out explicitly. We deliberately do NOT honor inline
# ARGO_SECURITY / ARGO_SECURITY_GUARD assignments — letting a command disable
# the guard would itself be a bypass.
if grep -qE '(^|[[:space:]])ARGO_CONSENT_GRANTED=once([[:space:]]|$)' <<< "$COMMAND"; then
  export ARGO_CONSENT_GRANTED=once
fi

# Word/path/quote-aware presence check: skip only when no `sf` command word
# appears anywhere (basename match, optional leading path or quote).
sf_word_present() {
  printf '%s' "$1" | awk '
    function base(s){ sub(/.*\//,"",s); gsub(/^["\047]+|["\047]+$/,"",s); return s }
    { for (i=1;i<=NF;i++) if (base($i)=="sf") { print "1"; exit } }
  ' | grep -q 1
}
if ! sf_word_present "$COMMAND" && ! grep -qE '\bsf[[:space:]]+force:' <<< "$COMMAND"; then
  exit 0
fi

# Source the security library + config helpers.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -z "$PLUGIN_ROOT" ]] || [[ ! -f "${PLUGIN_ROOT}/hooks/lib/security.sh" ]]; then
  # Library missing — the library is the source of truth for the metadata
  # allowlist. Without it we can't make a confident decision; fail closed for
  # known-dangerous patterns, fail open otherwise.
  if _looks_dangerous "$COMMAND"; then
    echo "[argo/security-guard] CLAUDE_PLUGIN_ROOT not set / library missing; refusing potentially-dangerous sf command" >&2
    exit 2
  fi
  exit 0
fi

# shellcheck source=/dev/null
source "${PLUGIN_ROOT}/hooks/lib/security.sh"

# --- Per-segment helpers ------------------------------------------------------

# Capture --target-org / -o <alias> in a segment; empty if absent.
extract_target_org() {
  local cmd="$1"
  printf '%s' "$cmd" | grep -oE -- '(--target-org|-o)[[:space:]]+[A-Za-z0-9._@+-]+' | head -1 | awk '{print $2}'
}

# Print the normalized "sf <verb> <noun>" for a segment, resolving a
# path-qualified or quoted `sf` (e.g. /usr/local/bin/sf, 'sf') to a bare verb
# tail. Empty when the segment does not invoke sf.
sf_invoke_of() {
  printf '%s' "$1" | awk '
    function base(s){ sub(/.*\//,"",s); gsub(/^["\047]+|["\047]+$/,"",s); return s }
    {
      for (i=1;i<=NF;i++) if (base($i)=="sf") {
        v=(i+1<=NF)?base($(i+1)):""; n=(i+2<=NF)?base($(i+2)):"";
        if (v !~ /^[a-z][a-z-]*$/) v="";
        if (n !~ /^[a-z][a-z-]*$/) n="";
        out="sf"; if (v!="") out=out" "v; if (v!="" && n!="") out=out" "n;
        print out; exit
      }
    }
  '
}

# classify_segment <segment> <sf-invoke>
# Returns 0 to allow the segment, 2 to refuse (sec_* emits the JSON event).
classify_segment() {
  local SEG="$1"
  local SF_INVOKE="$2"
  local ALIAS rc

  ALIAS=$(extract_target_org "$SEG")
  if [[ -z "$ALIAS" ]]; then
    ALIAS=$(sf_config_get '.platform.defaultTargetOrg // empty' "${SF_ENV:-}" 2>/dev/null || echo "")
  fi

  # Legacy `sf force:data:*` / `sf force:apex:execute` colon form.
  if grep -qE '\bsf[[:space:]]+force:data:' <<< "$SEG"; then
    sec_check_data_write "$ALIAS" "data-write"; return $?
  fi
  if grep -qE '\bsf[[:space:]]+force:apex:execute' <<< "$SEG"; then
    sec_check_anon_apex "$ALIAS"; return $?
  fi

  case "$SF_INVOKE" in
    "sf org list"|"sf alias list")
      return 0
      ;;
    "sf org display"|"sf org open")
      [[ -n "$ALIAS" ]] && { sec_check_org "$ALIAS"; rc=$?; [[ $rc -ne 0 ]] && return 2; }
      return 0
      ;;
    "sf project deploy"|"sf project retrieve"|"sf metadata deploy"|"sf metadata retrieve"|"sf source push"|"sf source pull")
      [[ -n "$ALIAS" ]] && { sec_check_org "$ALIAS"; rc=$?; [[ $rc -ne 0 ]] && return 2; }
      return 0
      ;;
    "sf sobject describe"|"sf sobject list"|"sf schema generate")
      [[ -n "$ALIAS" ]] && { sec_check_org "$ALIAS"; rc=$?; [[ $rc -ne 0 ]] && return 2; }
      return 0
      ;;
    "sf data query")
      local SOQL
      SOQL=$(printf '%s' "$SEG" | grep -oE -- '--query[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:]]+)' | head -1 | sed -E 's/^--query[[:space:]]+//; s/^["'\'']//; s/["'\'']$//')
      if [[ -z "$SOQL" ]]; then
        _sec_emit "refused" "SOQL_NOT_PARSEABLE" "soql" "" "$ALIAS" \
          "Could not extract --query argument from sf data query command. Quote the SOQL with single or double quotes."
        return 2
      fi
      sec_check_soql "$SOQL" "$ALIAS"; rc=$?
      [[ $rc -ne 0 ]] && return 2
      return 0
      ;;
    "sf data create-record"|"sf data update-record"|"sf data delete-record"|"sf data upsert"|"sf data import"|"sf data export"|"sf data tree"|"sf data create-bulk"|"sf data update-bulk")
      sec_check_data_write "$ALIAS" "data-write"; rc=$?
      [[ $rc -ne 0 ]] && return 2
      return 0
      ;;
    "sf apex run")
      if grep -qE '\bsf[[:space:]]+apex[[:space:]]+run[[:space:]]+test\b' <<< "$SEG"; then
        [[ -n "$ALIAS" ]] && { sec_check_org "$ALIAS"; rc=$?; [[ $rc -ne 0 ]] && return 2; }
        return 0
      fi
      sec_check_anon_apex "$ALIAS"; rc=$?
      [[ $rc -ne 0 ]] && return 2
      return 0
      ;;
    "sf agent run"|"sf agent test"|"sf agent generate")
      case "$SF_INVOKE" in
        "sf agent test"|"sf agent run")
          sec_check_data_write "$ALIAS" "agent-eval"; rc=$?
          [[ $rc -ne 0 ]] && return 2
          ;;
        *)
          [[ -n "$ALIAS" ]] && { sec_check_org "$ALIAS"; rc=$?; [[ $rc -ne 0 ]] && return 2; }
          ;;
      esac
      return 0
      ;;
    *)
      # Unrecognized subcommand. Be conservative: gate by org classification.
      [[ -n "$ALIAS" ]] && { sec_check_org "$ALIAS"; rc=$?; [[ $rc -ne 0 ]] && return 2; }
      return 0
      ;;
  esac
}

# --- Split on shell separators and gate EVERY sf-bearing segment --------------

status=0
while IFS= read -r SEG; do
  [[ -z "${SEG//[[:space:]]/}" ]] && continue
  INV=$(sf_invoke_of "$SEG")
  if [[ -z "$INV" ]] && ! grep -qE '\bsf[[:space:]]+force:' <<< "$SEG"; then
    continue
  fi
  classify_segment "$SEG" "$INV" || { status=2; break; }
done < <(printf '%s\n' "$COMMAND" | sed -E 's/\|\||&&|\||;|&/\n/g')

exit "$status"
