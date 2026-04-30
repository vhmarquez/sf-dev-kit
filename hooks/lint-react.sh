#!/bin/bash
# lint-react.sh — Format and lint React-on-Salesforce source files after Claude Code edits.
#
# Triggered by the PostToolUse hook on Edit|Write of .tsx / .jsx files inside
# the configured React source directory. Runs Prettier (write mode, non-blocking)
# and ESLint (report mode). Findings are surfaced on stderr.
#
# This is the React-side parallel to lint-lwc.sh and lint-apex.sh. Like those,
# it never blocks the edit (always exits 0).

set -u

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE_PATH" ]] && exit 0

# Resolve React source path from project config.
CONFIG_FILE="${CLAUDE_PROJECT_DIR}/.claude/sf-project.json"
REACT_SOURCE="force-app/main/default/react"
FRONTEND="lwc"

if [[ -f "$CONFIG_FILE" ]]; then
  configured=$(jq -r '.paths.reactSource // empty' "$CONFIG_FILE" 2>/dev/null)
  [[ -n "$configured" ]] && REACT_SOURCE="$configured"
  FRONTEND=$(jq -r '.platform.frontend // "lwc"' "$CONFIG_FILE" 2>/dev/null)
fi

# Bail out cleanly if React isn't enabled for this project.
case "$FRONTEND" in
  *react*) ;;
  *) exit 0 ;;
esac

REACT_ESCAPED=$(printf '%s' "$REACT_SOURCE" | sed 's/[.[\*^$/]/\\&/g')

# Scope: only React component files inside the configured source.
if [[ ! "$FILE_PATH" =~ ${REACT_ESCAPED}/.*\.(tsx|jsx|ts|js)$ ]]; then
  exit 0
fi

# Skip test files (they have their own conventions and may import test-only APIs)
if [[ "$FILE_PATH" =~ \.test\.(tsx|jsx|ts|js)$ ]] || [[ "$FILE_PATH" =~ __tests__ ]]; then
  exit 0
fi

# --- Prettier ----------------------------------------------------------------
prettier_out=$(npx --no-install prettier --write "$FILE_PATH" 2>&1)
prettier_exit=$?
if [[ $prettier_exit -ne 0 ]]; then
  {
    echo "[argo/lint-react] Prettier failed on $FILE_PATH (exit $prettier_exit):"
    echo "$prettier_out"
  } >&2
fi

# --- ESLint ------------------------------------------------------------------
# ESLint exits non-zero when it finds problems. Surface clearly; never block.
eslint_out=$(npx --no-install eslint "$FILE_PATH" 2>&1)
eslint_exit=$?
if [[ $eslint_exit -ne 0 ]]; then
  {
    echo "[argo/lint-react] ESLint findings on $FILE_PATH:"
    echo "$eslint_out"
  } >&2
fi

exit 0
