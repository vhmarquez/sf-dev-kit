#!/bin/bash
# config.sh — Load argo project config with optional per-environment overrides.
#
# Resolution order:
#   1. Base:     ${CLAUDE_PROJECT_DIR}/.claude/sf-project.json
#   2. Override: ${CLAUDE_PROJECT_DIR}/.claude/sf-project.<env>.json (deep-merged on top of base)
#
# Public functions:
#   sf_config_load   [env]              — print merged config JSON to stdout
#   sf_config_get    <jq-path> [env]    — print a single config value (uses jq -r)
#   sf_config_envs                      — list available env override names
#
# Requires: jq

sf_config_base_path() {
  echo "${CLAUDE_PROJECT_DIR}/.claude/sf-project.json"
}

sf_config_override_path() {
  local env="$1"
  echo "${CLAUDE_PROJECT_DIR}/.claude/sf-project.${env}.json"
}

sf_config_check_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "[argo] Error: jq is required. Install from https://stedolan.github.io/jq/" >&2
    return 1
  fi
}

sf_config_load() {
  local env="${1:-}"
  local base override
  base="$(sf_config_base_path)"

  if [[ ! -f "$base" ]]; then
    echo "[argo] Error: ${base} not found. Run /argo:sf-init first." >&2
    return 1
  fi

  sf_config_check_jq || return 1

  if [[ -n "$env" ]]; then
    override="$(sf_config_override_path "$env")"
    if [[ -f "$override" ]]; then
      # jq's `*` operator does recursive object merge; arrays are replaced
      jq -s '.[0] * .[1]' "$base" "$override"
      return 0
    else
      echo "[argo] Warning: env override ${override} not found; using base config" >&2
    fi
  fi

  cat "$base"
}

sf_config_get() {
  local path="$1"
  local env="${2:-}"
  if [[ -z "$path" ]]; then
    echo "[argo] Error: sf_config_get requires a jq path (e.g., '.platform.defaultTargetOrg')" >&2
    return 2
  fi
  sf_config_load "$env" | jq -r "$path"
}

sf_config_envs() {
  local dir="${CLAUDE_PROJECT_DIR}/.claude"
  [[ -d "$dir" ]] || return 0
  ls "$dir"/sf-project.*.json 2>/dev/null | while read -r f; do
    basename "$f" | sed -E 's/^sf-project\.(.+)\.json$/\1/'
  done
}
