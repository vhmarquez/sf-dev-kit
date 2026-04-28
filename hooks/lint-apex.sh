#!/bin/bash
# lint-apex.sh — Run a fast PMD scan against an edited Apex file.
#
# Triggered by the PostToolUse hook on Edit|Write of .cls / .trigger files.
# Runs PMD with a minimal ruleset (errorprone + a subset of bestpractices)
# tuned for fast feedback on save. The full security ruleset lives behind
# /sf-dev-kit:security-scan; this hook is only for "did I forget a semicolon
# / typo / obvious bug" feedback.
#
# Findings are surfaced on stderr; exit is always 0 (never blocks the edit).

set -u

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE_PATH" ]] && exit 0

# Resolve Apex source path.
CONFIG_FILE="${CLAUDE_PROJECT_DIR}/.claude/sf-project.json"
APEX_SRC="force-app/main/default/classes"
if [[ -f "$CONFIG_FILE" ]]; then
  configured=$(jq -r '.paths.apexSource // empty' "$CONFIG_FILE" 2>/dev/null)
  [[ -n "$configured" ]] && APEX_SRC="$configured"
fi

APEX_ESCAPED=$(printf '%s' "$APEX_SRC" | sed 's/[.[\*^$/]/\\&/g')

# Scope: only Apex .cls / .trigger files in the configured source.
if ! [[ "$FILE_PATH" =~ ${APEX_ESCAPED}/.*\.(cls|trigger)$ ]]; then
  exit 0
fi

# Skip test classes and -meta.xml (only -meta.xml triggers when separately edited).
if [[ "$FILE_PATH" =~ Test\.(cls|trigger)$ ]] || [[ "$FILE_PATH" =~ \.cls-meta\.xml$ ]] || [[ "$FILE_PATH" =~ \.trigger-meta\.xml$ ]]; then
  exit 0
fi

# Source the PMD helper. Fail soft if the plugin lib isn't reachable
# (the user may have moved files); the hook should never break their flow.
PMD_LIB="${CLAUDE_PLUGIN_ROOT:-}/hooks/lib/pmd.sh"
if [[ ! -f "$PMD_LIB" ]]; then
  exit 0
fi
# shellcheck source=/dev/null
source "$PMD_LIB"

# Use a small fast ruleset for incremental feedback. The full apex-security
# scan lives behind /sf-dev-kit:security-scan and is not run on every edit.
RULESET="category/apex/errorprone.xml,category/apex/bestpractices.xml"

pmd_out=$(pmd_run check --rulesets "$RULESET" --format text --no-progress --dir "$FILE_PATH" 2>&1)
pmd_exit=$?

if [[ $pmd_exit -ne 0 ]] || [[ -n "$pmd_out" ]]; then
  {
    echo "[sf-dev-kit/lint-apex] PMD findings on $FILE_PATH:"
    echo "$pmd_out"
    echo ""
    echo "(Run /sf-dev-kit:security-scan for the full security ruleset.)"
  } >&2
fi

exit 0
