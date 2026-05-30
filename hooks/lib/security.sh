#!/bin/bash
# security.sh — Centralized security gate for argo org-touching operations.
#
# # Invariants
#
#   1. No contact with orgs classified as production (security.prodOrgAliases).
#      Every `sf` invocation that targets such an alias is refused — including reads.
#   2. SOQL queries are restricted to a metadata allowlist by default. Customer-data
#      objects (Account, Contact, custom __c, AgentSessionTrace, etc.) require
#      explicit per-call user consent.
#   3. Anonymous Apex (sf apex run) is refused by default. Even when enabled via
#      security.allowAnonymousApex, every invocation prompts for consent.
#   4. Overrides are runtime-only. There are no persistent "always allow"
#      grants — every restricted call prompts. This is by design.
#
# # Wire protocol
#
# When a check refuses, the function emits a structured JSON event on stderr and
# exits with one of:
#
#   77 — consent required. The assistant should present the JSON event to the
#        user, and on grant, re-invoke the same command with the env var
#        ARGO_CONSENT_GRANTED=once set. The library treats that env var as
#        a single-use override, then unsets it (so a second restricted call in
#        the same shell still prompts).
#   78 — hard refusal. Cannot be overridden in this session. The assistant should
#        explain to the user and not retry. Most prod-org refusals exit 78.
#   2  — invocation error (bad arguments, missing dependencies).
#
# # JSON event shape
#
#   {
#     "event":   "consent_required" | "refused",
#     "reason":  "<rule id>",                         # e.g., "PROD_ORG_BLOCKED"
#     "skill":   "<skill name from $SKILL_NAME if set>",
#     "action":  "soql" | "metadata-read" | "metadata-write" | "anon-apex" | "data-write" | "data-read",
#     "target":  "<sObject API name | command tail | empty>",
#     "org":     "<alias>",
#     "message": "<one-line human description>"
#   }
#
# # Public functions
#
#   sec_check_org      <alias>             — block prod aliases; classify unclassified orgs
#   sec_check_soql     <soql> <alias>      — block non-allowlist SOQL targets
#   sec_check_anon_apex <alias>            — block anonymous Apex unless allowed
#   sec_check_data_write <alias> <action>  — block all data writes unless override
#   sec_metadata_allowlist                  — print the metadata allowlist (one per line)
#   sec_log_consent    <skill> <action> <scope> <decision>
#                                           — append to consent log JSONL
#   sec_classify_org   <alias>              — fetch and cache sandbox/prod state
#   sec_is_disabled                          — true when ARGO_SECURITY=0 (NOT recommended; for tests)

# shellcheck shell=bash

# --- Setup -------------------------------------------------------------------

if ! declare -F sf_config_get >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
fi

SEC_DATA_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data}/argo"
SEC_CACHE_DIR="${SEC_DATA_DIR}/org-cache"
# Key the decision log on the project's leaf name PLUS a short hash of its full
# path, so two unrelated projects that share a directory name (e.g. ~/work/x and
# ~/personal/x) never write to the same audit file. cksum is POSIX-portable.
SEC_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-unknown}"
SEC_PROJECT_SLUG="$(basename "$SEC_PROJECT_DIR")-$(printf '%s' "$SEC_PROJECT_DIR" | cksum | cut -d' ' -f1)"
SEC_CONSENT_LOG="${SEC_DATA_DIR}/consent-log/${SEC_PROJECT_SLUG}.jsonl"

# Classification cache entries older than this are re-derived (so an alias that
# is re-authed to a different org cannot ride a stale verdict forever).
SEC_CACHE_TTL_SECONDS="${ARGO_ORG_CACHE_TTL:-604800}"  # 7 days

# These directories hold org metadata and consent history — keep them owner-only.
mkdir -p "${SEC_CACHE_DIR}" "$(dirname "$SEC_CONSENT_LOG")" 2>/dev/null
chmod 700 "${SEC_DATA_DIR}" "${SEC_CACHE_DIR}" "$(dirname "$SEC_CONSENT_LOG")" 2>/dev/null

# --- Allowlist: SOQL targets considered metadata --------------------------------
# Conservative; expansion requires reviewer sign-off + consent-log audit.

SEC_METADATA_OBJECTS=(
  # Schema definitions
  EntityDefinition FieldDefinition EntityParticle RelationshipInfo RelationshipDomain
  CustomObject CustomField CustomMetadataType
  # Apex / UI source
  ApexClass ApexTrigger ApexComponent ApexPage
  AuraDefinition AuraDefinitionBundle
  LightningComponentBundle LightningComponentResource
  StaticResource StaticResourceMetadata
  # Test results (metadata-shaped — not customer data)
  ApexCodeCoverage ApexCodeCoverageAggregate
  ApexTestResult ApexTestRunResult ApexTestSuite TestSuiteMembership
  # Flow definitions (NOT FlowInterview which has runtime data)
  Flow FlowDefinition FlowDefinitionView FlowVersionView
  # Permission definitions (NOT PermissionSetAssignment which links to specific users)
  Profile PermissionSet PermissionSetGroup PermissionSetGroupComponent
  ObjectPermissions FieldPermissions SetupEntityAccess
  # Org info / limits
  Organization Limits BackgroundOperation OrgWideEmailAddress
  # Setup metadata
  RecordType BusinessProcess Layout ValidationRule
  CustomLabel CustomTab CustomApplication AppDefinition AppMenuItem
  # Agent definitions (NOT AgentSessionTrace, NOT AgentInteractionLog)
  AgentDefinition AgentVersion AgentTopic AgentRegistryEntry
  # Named credentials & auth (definitions; secrets aren't queryable)
  NamedCredential ExternalCredential AuthProvider ConnectedApplication
  # CMS / catalog structure (NOT content-versioned bodies which can carry PII)
  ManagedContentType ManagedContentChannel
  # Platform Event / CDC channel definitions
  PlatformEventSubscriberConfig PlatformEventChannel PlatformEventChannelMember
)

sec_is_metadata_target() {
  local target="$1"
  [[ -z "$target" ]] && return 1

  # __mdt suffix → Custom Metadata Type record (definitionally metadata)
  case "$target" in
    *__mdt) return 0 ;;
  esac

  # Exact-match allowlist
  local m
  for m in "${SEC_METADATA_OBJECTS[@]}"; do
    [[ "$target" == "$m" ]] && return 0
  done
  return 1
}

sec_metadata_allowlist() {
  printf '%s\n' "${SEC_METADATA_OBJECTS[@]}"
  echo "*__mdt"
}

# --- Disable switch (NOT recommended) -----------------------------------------

sec_is_disabled() {
  [[ "${ARGO_SECURITY:-1}" == "0" ]]
}

# --- Consent token (single-use) ------------------------------------------------

sec_consent_granted_once() {
  [[ "${ARGO_CONSENT_GRANTED:-}" == "once" ]]
}

# Consume the token so a second restricted call in the same process must prompt again.
sec_consent_consume() {
  unset ARGO_CONSENT_GRANTED
}

# --- Org classification --------------------------------------------------------

sec_org_cache_path() {
  local alias="$1"
  echo "${SEC_CACHE_DIR}/${alias}.json"
}

# True when the alias resolves to a scratch org per `sf org list`. Scratch orgs
# are ephemeral, Dev-Hub-created dev targets — never production — so they are
# treated as a non-prod "dev" tier and allowed without explicit classification.
# Matches on alias OR username. A production org cannot appear in scratchOrgs,
# so this signal can never promote a prod org to allowed.
sec_is_scratch_alias() {
  local alias="$1"
  command -v sf >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  sf org list --json 2>/dev/null \
    | jq -e --arg a "$alias" '[.result.scratchOrgs // [] | .[]?] | any(.alias == $a or .username == $a)' >/dev/null 2>&1
}

# Print "sandbox" | "dev" | "prod" | "unknown" ("dev" = scratch org, non-prod).
# Fetches via `sf org display` once and caches. The cache is treated as a
# performance hint, not a trust anchor: the
# definitive prod allowlist (security.prodOrgAliases) is consulted by
# sec_check_org BEFORE this function on every call, so a tampered or stale
# cache cannot promote a listed prod org to "sandbox". Cached verdicts also
# expire (SEC_CACHE_TTL_SECONDS) and "unknown" is never cached, so transient
# failures and alias re-auth self-heal.
sec_classify_org() {
  local alias="$1"
  local cache; cache="$(sec_org_cache_path "$alias")"

  if [[ -f "$cache" ]]; then
    local cached_cls cached_at age now
    cached_cls=$(jq -r '.classification // "unknown"' "$cache" 2>/dev/null || echo "unknown")
    cached_at=$(jq -r '.classifiedAtEpoch // 0' "$cache" 2>/dev/null || echo 0)
    now=$(date -u +%s 2>/dev/null || echo 0)
    age=$(( now - cached_at ))
    # Only honor a definitive, non-expired verdict; otherwise fall through and re-derive.
    if [[ "$cached_cls" == "sandbox" || "$cached_cls" == "dev" || "$cached_cls" == "prod" ]] && (( cached_at > 0 && age >= 0 && age < SEC_CACHE_TTL_SECONDS )); then
      echo "$cached_cls"
      return 0
    fi
  fi

  command -v sf >/dev/null 2>&1 || { echo "unknown"; return 0; }
  command -v jq >/dev/null 2>&1 || { echo "unknown"; return 0; }

  local info
  info=$(sf org display --target-org "$alias" --json 2>/dev/null) || { echo "unknown"; return 0; }

  local is_sandbox
  # NB: do NOT use jq's `//` here — it coalesces a literal `false` to the next
  # branch, which would mislabel a prod org (isSandbox=false) as unparseable.
  is_sandbox=$(printf '%s' "$info" | jq -r 'if .result.isSandbox != null then (.result.isSandbox|tostring) elif .result.sandbox != null then (.result.sandbox|tostring) else "" end' 2>/dev/null)

  local cls="unknown"
  if sec_is_scratch_alias "$alias"; then
    # Scratch org — ephemeral dev target, never prod. Allowed as "dev".
    cls="dev"
  else
    case "$is_sandbox" in
      true)  cls="sandbox" ;;
      false) cls="prod" ;;
    esac
  fi

  # Never cache "unknown" — that would pin the alias to a permanent failed
  # state. Only persist a definitive verdict, with a username + epoch stamp so
  # a later alias re-auth (different org behind the same alias) is detectable.
  if [[ "$cls" == "sandbox" || "$cls" == "dev" || "$cls" == "prod" ]]; then
    local username tmp
    username=$(printf '%s' "$info" | jq -r '.result.username // empty' 2>/dev/null)
    # Write to a temp file then atomically rename, so a concurrent reader never
    # sees a half-written cache (mv is atomic on the same filesystem).
    tmp="${cache}.tmp.$$"
    if jq -n --arg a "$alias" --arg c "$cls" --arg u "$username" \
         --arg t "$(date -u +%FT%TZ)" --argjson e "$(date -u +%s)" \
         '{alias:$a, classification:$c, username:$u, classifiedAt:$t, classifiedAtEpoch:$e}' > "$tmp" 2>/dev/null; then
      chmod 600 "$tmp" 2>/dev/null
      mv -f "$tmp" "$cache" 2>/dev/null || rm -f "$tmp"
    fi
  fi

  echo "$cls"
}

# --- Decision log (audit trail) -------------------------------------------------
#
# Records EVERY org-access decision — grants AND denials/consent prompts — as one
# JSON line, so the file is a true audit trail rather than a grants-only record.
# Each line: {ts, decision, reason, skill, action, target, org}. A single jq line
# written with O_APPEND is below PIPE_BUF, so concurrent appends from parallel
# agents stay intact without a lock (which isn't portable to macOS anyway).

_sec_audit() {  # decision reason skill action target org
  jq -n -c \
    --arg t "$(date -u +%FT%TZ)" \
    --arg d "${1:-unknown}" --arg r "${2:-}" --arg s "${3:-unknown}" \
    --arg a "${4:-unknown}" --arg tg "${5:-}" --arg o "${6:-}" \
    '{ts:$t, decision:$d, reason:$r, skill:$s, action:$a, target:$tg, org:$o}' >> "$SEC_CONSENT_LOG" 2>/dev/null
  chmod 600 "$SEC_CONSENT_LOG" 2>/dev/null
}

# Backward-compatible grant logger (allow-once / metadata-only-disabled).
sec_log_consent() {
  _sec_audit "${4:-unknown}" "" "${1:-unknown}" "${2:-unknown}" "${3:-}" ""
}

# --- Refusal helpers -----------------------------------------------------------

# Emit a refused or consent_required event on stderr AND record it to the audit
# log, so blocked prod attempts and consent prompts are captured, not just grants.
# Args: event reason action target org message
_sec_emit() {
  local ev="$1" reason="$2" action="$3" target="$4" org="$5" msg="$6"
  jq -n -c \
    --arg ev "$ev" --arg reason "$reason" \
    --arg skill "${SKILL_NAME:-unknown}" \
    --arg action "$action" --arg target "$target" --arg org "$org" \
    --arg msg "$msg" \
    '{event:$ev, reason:$reason, skill:$skill, action:$action, target:$target, org:$org, message:$msg}' >&2
  _sec_audit "$ev" "$reason" "${SKILL_NAME:-unknown}" "$action" "$target" "$org"
}

# --- The checks ----------------------------------------------------------------

# sec_check_org <alias>
# Returns 0 if the alias is safe to use; 78 if hard-refused (prod); 77 if
# consent required (unclassified non-sandbox).
sec_check_org() {
  local alias="$1"
  if [[ -z "$alias" ]]; then
    echo "[argo/security] sec_check_org requires an alias" >&2
    return 2
  fi

  if sec_is_disabled; then
    return 0
  fi

  # Explicit prod allowlist — hard refuse, no override.
  local prod_aliases
  prod_aliases=$(sf_config_get '.security.prodOrgAliases // [] | join("\n")' "${SF_ENV:-}" 2>/dev/null || echo "")
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if [[ "$p" == "$alias" ]]; then
      _sec_emit "refused" "PROD_ORG_BLOCKED" "any" "" "$alias" \
        "Org '$alias' is classified as production in security.prodOrgAliases. Plugin invocations on prod orgs are refused unconditionally."
      return 78
    fi
  done <<< "$prod_aliases"

  # Known non-sandbox-but-not-prod (dev orgs, demo orgs) — allowed.
  local known_nonprod
  known_nonprod=$(sf_config_get '.security.knownNonSandboxNonProd // [] | join("\n")' "${SF_ENV:-}" 2>/dev/null || echo "")
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    [[ "$p" == "$alias" ]] && return 0
  done <<< "$known_nonprod"

  # Unknown classification — fetch + decide.
  local cls; cls="$(sec_classify_org "$alias")"
  case "$cls" in
    sandbox|dev)
      # sandbox or scratch ("dev") — non-prod, allowed without classification.
      return 0
      ;;
    prod)
      if sec_consent_granted_once; then
        # Even with consent, refuse — prod is hard.
        sec_consent_consume
        _sec_emit "refused" "PROD_ORG_DETECTED_NO_OVERRIDE" "any" "" "$alias" \
          "Org '$alias' is non-sandbox per 'sf org display' (isSandbox=false). Even with consent, the plugin will not contact prod. Add to security.prodOrgAliases (recommended) or security.knownNonSandboxNonProd if it's a dev/demo org you want to allow."
        return 78
      fi
      _sec_emit "consent_required" "ORG_UNCLASSIFIED_NONSANDBOX" "classify" "" "$alias" \
        "Org '$alias' is non-sandbox per 'sf org display' and is not yet classified. Classify it as production (security.prodOrgAliases) or as a known dev/demo org (security.knownNonSandboxNonProd)."
      return 77
      ;;
    unknown|*)
      _sec_emit "consent_required" "ORG_CLASSIFICATION_FAILED" "classify" "" "$alias" \
        "Could not classify org '$alias' (sf org display failed or alias unknown). Verify the alias resolves and retry; or add to a security.* list to skip classification."
      return 77
      ;;
  esac
}

# sec_check_soql <soql> <alias>
# Returns 0 if the SOQL targets are all on the metadata allowlist; 77 if any
# target is data and consent has not been granted.
sec_check_soql() {
  local soql="$1"
  local alias="${2:-}"
  if [[ -z "$soql" ]]; then
    echo "[argo/security] sec_check_soql requires a SOQL string" >&2
    return 2
  fi

  if sec_is_disabled; then
    return 0
  fi

  # Org check first (so a prod-targeted query never reaches the FROM parser).
  if [[ -n "$alias" ]]; then
    sec_check_org "$alias" || return $?
  fi

  # Parse FROM <Object> (case-insensitive). SOQL only allows one root FROM.
  local target
  target=$(printf '%s' "$soql" | grep -ioE 'FROM[[:space:]]+[A-Za-z0-9_]+' | head -1 | awk '{print $2}')
  if [[ -z "$target" ]]; then
    _sec_emit "refused" "SOQL_PARSE_FAILED" "soql" "" "$alias" \
      "Could not extract FROM clause from SOQL. The plugin refuses queries it can't statically classify."
    return 78
  fi

  if sec_is_metadata_target "$target"; then
    return 0
  fi

  if sec_consent_granted_once; then
    sec_log_consent "${SKILL_NAME:-unknown}" "soql" "$target@$alias" "allow-once"
    sec_consent_consume
    return 0
  fi

  _sec_emit "consent_required" "SOQL_DATA_OBJECT" "soql" "$target" "$alias" \
    "SOQL target '$target' is not on the metadata allowlist. This query would read customer data. Use ARGO_CONSENT_GRANTED=once to authorize a single retry."
  return 77
}

# sec_check_anon_apex <alias>
# Always refuses unless security.allowAnonymousApex=true AND consent token set.
sec_check_anon_apex() {
  local alias="${1:-}"
  if sec_is_disabled; then
    return 0
  fi

  if [[ -n "$alias" ]]; then
    sec_check_org "$alias" || return $?
  fi

  local allowed
  allowed=$(sf_config_get '.security.allowAnonymousApex // false' "${SF_ENV:-}" 2>/dev/null || echo "false")
  if [[ "$allowed" != "true" ]]; then
    _sec_emit "refused" "ANON_APEX_DISABLED" "anon-apex" "" "$alias" \
      "Anonymous Apex (sf apex run) is disabled. Set security.allowAnonymousApex=true to enable; even then every call requires per-call consent."
    return 78
  fi

  if sec_consent_granted_once; then
    sec_log_consent "${SKILL_NAME:-unknown}" "anon-apex" "$alias" "allow-once"
    sec_consent_consume
    return 0
  fi

  _sec_emit "consent_required" "ANON_APEX_CONSENT" "anon-apex" "" "$alias" \
    "Anonymous Apex bypasses the metadata-only contract — it can read or write anything in the org. Confirm before each call."
  return 77
}

# sec_check_data_write <alias> <action>  (action: data-write | data-import | data-export | data-delete)
sec_check_data_write() {
  local alias="${1:-}"
  local action="${2:-data-write}"
  if sec_is_disabled; then
    return 0
  fi

  if [[ -n "$alias" ]]; then
    sec_check_org "$alias" || return $?
  fi

  if sec_consent_granted_once; then
    sec_log_consent "${SKILL_NAME:-unknown}" "$action" "$alias" "allow-once"
    sec_consent_consume
    return 0
  fi

  _sec_emit "consent_required" "DATA_WRITE_BLOCKED" "$action" "" "$alias" \
    "Data $action operations against an org touch customer records. Refused unless consent is granted per-call."
  return 77
}
