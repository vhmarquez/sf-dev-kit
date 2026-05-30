#!/usr/bin/env bats
# PMD lazy-installer integrity helpers (hooks/lib/pmd.sh). The full download path
# needs network, so we test the hashing helper and the pinned-hash invariant that
# the fail-closed verification depends on.

load 'helpers/common'

@test "_pmd_sha256 matches the system hasher" {
  source "$PLUGIN_ROOT/hooks/lib/pmd.sh"
  printf 'argo-pmd-test' > "$TEST_TMP/blob"
  expected=$(shasum -a 256 "$TEST_TMP/blob" | awk '{print $1}')
  run _pmd_sha256 "$TEST_TMP/blob"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "the default PMD version carries a pinned 64-char sha256" {
  source "$PLUGIN_ROOT/hooks/lib/pmd.sh"
  [ -n "$PMD_SHA256_DEFAULT" ]
  [ "${#PMD_SHA256_DEFAULT}" -eq 64 ]
}

@test "the pinned hash applies to the default PMD version (so verification is active out of the box)" {
  source "$PLUGIN_ROOT/hooks/lib/pmd.sh"
  [ "$PMD_VERSION" = "$PMD_SHA256_DEFAULT_VERSION" ]
}
