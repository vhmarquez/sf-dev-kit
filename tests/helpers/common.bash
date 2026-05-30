# Shared helpers for argo hook tests (sourced by every .bats file).
# Provides setup/teardown that isolate every test under a temp dir with a fake
# `sf`, plus convenience wrappers around the hooks.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

  TEST_TMP="$(mktemp -d)"
  export CLAUDE_PROJECT_DIR="$TEST_TMP/proj"
  export CLAUDE_PLUGIN_DATA="$TEST_TMP/data"
  mkdir -p "$CLAUDE_PROJECT_DIR/.claude" "$CLAUDE_PLUGIN_DATA/argo/org-cache"

  # Fake `sf` shadows the real one; keep /usr/bin etc. for jq/awk/sed/date.
  export PATH="$BATS_TEST_DIRNAME/helpers:$PATH"
  chmod +x "$BATS_TEST_DIRNAME/helpers/sf" 2>/dev/null || true

  # Default org topology used by most tests (individual tests can override).
  export FAKE_SF_SCRATCH="scr1"
  export FAKE_SF_SANDBOX="sb1"
  export FAKE_SF_NONSCRATCH="prod1 okdev prodlisted"

  # Default config: one hard-blocked prod alias, one allowed dev alias.
  write_config '{
    "platform": { "defaultTargetOrg": "sb1" },
    "security": {
      "prodOrgAliases": ["prodlisted"],
      "knownNonSandboxNonProd": ["okdev"],
      "allowAnonymousApex": false
    }
  }'
}

teardown() {
  [[ -n "${TEST_TMP:-}" ]] && rm -rf "$TEST_TMP"
}

# write_config <json> — replace the project's sf-project.json.
write_config() {
  printf '%s' "$1" > "$CLAUDE_PROJECT_DIR/.claude/sf-project.json"
}

# seed_cache <alias> <classification> [age_seconds] — write a classification
# verdict (default fresh; pass a large age to simulate an expired entry).
seed_cache() {
  local alias="$1" cls="$2" age="${3:-0}" now
  now=$(( $(date -u +%s) - age ))
  printf '{"alias":"%s","classification":"%s","username":"u@example.com","classifiedAtEpoch":%s}' \
    "$alias" "$cls" "$now" > "$CLAUDE_PLUGIN_DATA/argo/org-cache/$alias.json"
}

# guard <command-string> — run the PreToolUse Bash guard on a command.
# Populates $status (0 allow / 2 block) and $output (stderr JSON event).
guard() {
  printf '%s' "$1" | jq -Rs '{tool_input:{command:.}}' \
    | bash "$PLUGIN_ROOT/hooks/security-guard.sh" 2>&1
}

# Source the security library into the current shell for direct function tests.
load_security_lib() {
  # shellcheck source=/dev/null
  source "$PLUGIN_ROOT/hooks/lib/security.sh"
}
