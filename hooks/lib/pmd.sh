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

# SHA-256 of the official pmd-dist-<version>-bin.zip GitHub release asset, pinned
# for the default version. When bumping ARGO_PMD_VERSION, pass the matching hash
# via ARGO_PMD_SHA256 (otherwise the integrity check warns and is skipped).
PMD_SHA256_DEFAULT_VERSION="7.6.0"
PMD_SHA256_DEFAULT="e07f7a9c3607d643509a96d7f5f891961e98ea88b6eba85d120d08f0c08c985e"

# Print the SHA-256 of a file using whatever hashing tool is available; empty if none.
_pmd_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  else
    echo ""
  fi
}

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

  # Verify integrity before extracting/executing. Expected hash is pinned for the
  # default version; override with ARGO_PMD_SHA256 for other versions. Fail closed
  # on mismatch (delete the artifact, refuse to extract).
  local expected="${ARGO_PMD_SHA256:-}"
  if [[ -z "$expected" && "$PMD_VERSION" == "$PMD_SHA256_DEFAULT_VERSION" ]]; then
    expected="$PMD_SHA256_DEFAULT"
  fi
  if [[ -n "$expected" ]]; then
    local actual; actual="$(_pmd_sha256 "$zip")"
    if [[ -z "$actual" ]]; then
      echo "[argo] Warning: no sha256 tool (shasum/sha256sum) found — cannot verify PMD download integrity." >&2
    elif [[ "$actual" != "$expected" ]]; then
      rm -f "$zip"
      echo "[argo] PMD checksum mismatch — refusing to extract." >&2
      echo "[argo]   expected: $expected" >&2
      echo "[argo]   actual:   $actual" >&2
      return 1
    fi
  else
    echo "[argo] Warning: no pinned SHA-256 for PMD ${PMD_VERSION}; skipping integrity check (set ARGO_PMD_SHA256 to enforce)." >&2
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
