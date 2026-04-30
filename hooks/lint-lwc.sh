#!/bin/bash
# lint-lwc.sh — Format and lint LWC JavaScript files after Claude Code edits.
#
# Runs Prettier (write mode, non-blocking) and ESLint (report mode) on the edited
# LWC JS file. The LWC source path is read from .claude/sf-project.json
# (paths.lwcSource); falls back to "force-app/main/default/lwc" if the config or
# jq is missing.
#
# Findings are surfaced on stderr so the assistant sees them. The hook always
# exits 0 — it never blocks the edit.

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  # jq is required to parse the hook input — if it's missing, silently no-op.
  exit 0
fi

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Resolve LWC source path from project config (with fallback).
CONFIG_FILE="${CLAUDE_PROJECT_DIR}/.claude/sf-project.json"
LWC_SOURCE="force-app/main/default/lwc"
if [[ -f "$CONFIG_FILE" ]]; then
  CONFIGURED=$(jq -r '.paths.lwcSource // empty' "$CONFIG_FILE" 2>/dev/null)
  if [[ -n "$CONFIGURED" ]]; then
    LWC_SOURCE="$CONFIGURED"
  fi
fi

LWC_SOURCE_ESCAPED=$(printf '%s' "$LWC_SOURCE" | sed 's/[.[\*^$/]/\\&/g')

# Scope: only LWC JS files, skipping __tests__.
if [[ ! "$FILE_PATH" =~ ${LWC_SOURCE_ESCAPED}/.*\.js$ ]]; then
  exit 0
fi
if [[ "$FILE_PATH" =~ __tests__ ]]; then
  exit 0
fi

# --- Prettier ----------------------------------------------------------------
prettier_out=$(npx --no-install prettier --write "$FILE_PATH" 2>&1)
prettier_exit=$?
if [[ $prettier_exit -ne 0 ]]; then
  {
    echo "[argo/lint-lwc] Prettier failed on $FILE_PATH (exit $prettier_exit):"
    echo "$prettier_out"
  } >&2
fi

# --- ESLint ------------------------------------------------------------------
# ESLint exits non-zero when it finds problems. We surface those clearly but
# never block the edit. If ESLint is not installed, npx will fail; report it.
eslint_out=$(npx --no-install eslint "$FILE_PATH" 2>&1)
eslint_exit=$?
if [[ $eslint_exit -ne 0 ]]; then
  {
    echo "[argo/lint-lwc] ESLint findings on $FILE_PATH:"
    echo "$eslint_out"
  } >&2
fi

exit 0
