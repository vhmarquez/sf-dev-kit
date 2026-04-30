#!/bin/bash
# security.sh — Centralized security gate for sf-dev-kit org-touching operations.
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
#        SF_DEV_KIT_CONSENT_GRANTED=once set. The library treats that env var as
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
#   sec_is_disabled                          — true when SF_DEV_KIT_SECURITY=0 (NOT recommended; for tests)

# shellcheck shell=bash

# --- Setup -------------------------------------------------------------------

if ! declare -F sf_config_get >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
fi

SEC_DATA_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data}/sf-dev-kit"
SEC_CACHE_DIR="${SEC_DATA_DIR}/org-cache"
SEC_CONSENT_LOG="${SEC_DATA_DIR}/consent-log/$(basename "${CLAUDE_PROJECT_DIR:-unknown}").jsonl"

mkdir -p "${SEC_CACHE_DIR}" "$(dirname "$SEC_CONSENT_LOG")" 2>/dev/null

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
  [[ "${SF_DEV_KIT_SECURITY:-1}" == "0" ]]
}

# --- Consent token (single-use) ------------------------------------------------

sec_consent_granted_once() {
  [[ "${SF_DEV_KIT_CONSENT_GRANTED:-}" == "once" ]]
}

# Consume the token so a second restricted call in the same process must prompt again.
sec_consent_consume() {
  unset SF_DEV_KIT_CONSENT_GRANTED
}

# --- Org classification --------------------------------------------------------

sec_org_cache_path() {
  local alias="$1"
  echo "${SEC_CACHE_DIR}/${alias}.json"
}

# Print "sandbox" | "prod" | "unknown". Fetches via `sf org display` once and caches.
sec_classify_org() {
  local alias="$1"
  local cache; cache="$(sec_org_cache_path "$alias")"

  if [[ -f "$cache" ]]; then
    jq -r '.classification // "unknown"' "$cache" 2>/dev/null || echo "unknown"
    return 0
  fi

  command -v sf >/dev/null 2>&1 || { echo "unknown"; return 0; }
  command -v jq >/dev/null 2>&1 || { echo "unknown"; return 0; }

  local info
  info=$(sf org display --target-org "$alias" --json 2>/dev/null) || { echo "unknown"; return 0; }

  local is_sandbox
  is_sandbox=$(printf '%s' "$info" | jq -r '.result.isSandbox // .result.sandbox // empty' 2>/dev/null)

  local cls="unknown"
  case "$is_sandbox" in
    true)  cls="sandbox" ;;
    false) cls="prod" ;;
  esac

  jq -n --arg a "$alias" --arg c "$cls" --arg t "$(date -u +%FT%TZ)" \
    '{alias:$a, classification:$c, classifiedAt:$t}' > "$cache" 2>/dev/null

  echo "$cls"
}

# --- Consent log ---------------------------------------------------------------

sec_log_consent() {
  local skill="${1:-unknown}"
  local action="${2:-unknown}"
  local scope="${3:-}"
  local decision="${4:-unknown}"
  jq -n -c \
    --arg t "$(date -u +%FT%TZ)" \
    --arg s "$skill" --arg a "$action" --arg sc "$scope" --arg d "$decision" \
    '{ts:$t, skill:$s, action:$a, scope:$sc, decision:$d}' >> "$SEC_CONSENT_LOG" 2>/dev/null
}

# --- Refusal helpers -----------------------------------------------------------

# Emit a refused or consent_required event.
# Args: event reason action target org message
_sec_emit() {
  local ev="$1" reason="$2" action="$3" target="$4" org="$5" msg="$6"
  jq -n -c \
    --arg ev "$ev" --arg reason "$reason" \
    --arg skill "${SKILL_NAME:-unknown}" \
    --arg action "$action" --arg target "$target" --arg org "$org" \
    --arg msg "$msg" \
    '{event:$ev, reason:$reason, skill:$skill, action:$action, target:$target, org:$org, message:$msg}' >&2
}

# --- The checks ----------------------------------------------------------------

# sec_check_org <alias>
# Returns 0 if the alias is safe to use; 78 if hard-refused (prod); 77 if
# consent required (unclassified non-sandbox).
sec_check_org() {
  local alias="$1"
  if [[ -z "$alias" ]]; then
    echo "[sf-dev-kit/security] sec_check_org requires an alias" >&2
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
    sandbox)
      return 0
      ;;
    prod)
      if sec_consent_granted_once; then
        # Even with consent, refuse — prod is hard.
        sec_consent_consume
        _sec_emit "refused" "PROD_ORG_DETECTED_NO_OVERRIDE" "any" "" "$alias" \
          "Org '$alias' is non-sandbox per `sf org display` (isSandbox=false). Even with consent, the plugin will not contact prod. Add to security.prodOrgAliases (recommended) or security.knownNonSandboxNonProd if it's a dev/demo org you want to allow."
        return 78
      fi
      _sec_emit "consent_required" "ORG_UNCLASSIFIED_NONSANDBOX" "classify" "" "$alias" \
        "Org '$alias' is non-sandbox per `sf org display` and is not yet classified. Classify it as production (security.prodOrgAliases) or as a known dev/demo org (security.knownNonSandboxNonProd)."
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
    echo "[sf-dev-kit/security] sec_check_soql requires a SOQL string" >&2
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
    "SOQL target '$target' is not on the metadata allowlist. This query would read customer data. Use SF_DEV_KIT_CONSENT_GRANTED=once to authorize a single retry."
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
