#!/bin/bash
# pmd.sh — Lazy PMD installer used by /security-scan, /dead-code, /complexity.
#
# Behavior: on first call, downloads the pinned PMD release into the plugin's
# data directory (${CLAUDE_PLUGIN_DATA}/argo/pmd/<version>/). Subsequent
# calls reuse the cached install. Pinned version lives in PMD_VERSION below.
#
# Public functions:
#   pmd_run        <args...>   — invoke PMD, installing first if missing
#   pmd_install_dir            — print the install directory for the pinned version
#   pmd_executable             — print the path to the pmd binary, empty if absent

PMD_VERSION="${ARGO_PMD_VERSION:-7.6.0}"

pmd_data_root() {
  local root="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data}/argo/pmd"
  echo "$root"
}

pmd_install_dir() {
  echo "$(pmd_data_root)/${PMD_VERSION}"
}

pmd_executable() {
  local dir; dir="$(pmd_install_dir)"
  if [[ -x "${dir}/pmd-bin-${PMD_VERSION}/bin/pmd" ]]; then
    echo "${dir}/pmd-bin-${PMD_VERSION}/bin/pmd"
  elif [[ -f "${dir}/pmd-bin-${PMD_VERSION}/bin/pmd.bat" ]]; then
    echo "${dir}/pmd-bin-${PMD_VERSION}/bin/pmd.bat"
  fi
}

pmd_install() {
  local exe; exe="$(pmd_executable)"
  [[ -n "$exe" ]] && return 0

  local dir; dir="$(pmd_install_dir)"
  mkdir -p "$dir"

  local url="https://github.com/pmd/pmd/releases/download/pmd_releases%2F${PMD_VERSION}/pmd-dist-${PMD_VERSION}-bin.zip"
  local zip="${dir}/pmd.zip"

  echo "[argo] Downloading PMD ${PMD_VERSION} (one-time, ~30 MB)..." >&2
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$zip" "$url" || { echo "[argo] PMD download failed: $url" >&2; return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$zip" "$url" || { echo "[argo] PMD download failed: $url" >&2; return 1; }
  else
    echo "[argo] Error: curl or wget is required to download PMD" >&2
    return 1
  fi

  if ! command -v unzip >/dev/null 2>&1; then
    echo "[argo] Error: unzip is required to extract PMD" >&2
    return 1
  fi

  unzip -q "$zip" -d "$dir" || { echo "[argo] PMD extract failed" >&2; return 1; }
  rm -f "$zip"

  exe="$(pmd_executable)"
  if [[ -z "$exe" ]]; then
    echo "[argo] Error: PMD executable not found after extract; expected pmd-bin-${PMD_VERSION}/bin/pmd[.bat]" >&2
    return 1
  fi

  echo "[argo] PMD ${PMD_VERSION} installed at ${dir}" >&2
  return 0
}

pmd_run() {
  pmd_install || return $?
  local exe; exe="$(pmd_executable)"
  "$exe" "$@"
}
