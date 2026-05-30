#!/usr/bin/env bats
# Org classification + access library (hooks/lib/security.sh), tested directly so
# we see the real library exit codes (77 consent / 78 hard refuse) that the guard
# collapses to exit 2.

load 'helpers/common'

@test "scratch org classifies as 'dev' and is allowed" {
  load_security_lib
  run sec_classify_org scr1
  [ "$output" = "dev" ]
  run sec_check_org scr1
  [ "$status" -eq 0 ]
}

@test "sandbox is allowed" {
  load_security_lib
  run sec_classify_org sb1
  [ "$output" = "sandbox" ]
  run sec_check_org sb1
  [ "$status" -eq 0 ]
}

@test "a real prod org (non-scratch, isSandbox=false) classifies as prod and is blocked (77)" {
  load_security_lib
  run sec_classify_org prod1
  [ "$output" = "prod" ]
  run sec_check_org prod1
  [ "$status" -eq 77 ]
}

@test "an alias in prodOrgAliases is hard-refused (78), even with consent" {
  load_security_lib
  run sec_check_org prodlisted
  [ "$status" -eq 78 ]
  export ARGO_CONSENT_GRANTED=once
  run sec_check_org prodlisted
  [ "$status" -eq 78 ]
}

@test "an alias in knownNonSandboxNonProd is allowed" {
  load_security_lib
  run sec_check_org okdev
  [ "$status" -eq 0 ]
}

@test "classification failure returns 'unknown' and is never cached" {
  export FAKE_SF_FAIL=1
  load_security_lib
  run sec_classify_org ghost
  [ "$output" = "unknown" ]
  [ ! -f "$CLAUDE_PLUGIN_DATA/argo/org-cache/ghost.json" ]
}

@test "an expired verdict is re-derived, not trusted" {
  seed_cache prod1 sandbox 700000   # stale 'sandbox' (>7d) for what is really a prod org
  load_security_lib
  run sec_classify_org prod1
  [ "$output" = "prod" ]            # re-derived; the stale sandbox verdict is ignored
}

@test "a fresh verdict is served from cache without contacting the org" {
  seed_cache sb1 sandbox 0
  export FAKE_SF_FAIL=1             # org display would fail if it were contacted
  load_security_lib
  run sec_classify_org sb1
  [ "$output" = "sandbox" ]        # cache short-circuits before any sf call
}

@test "metadata-only is unconditional: data SOQL needs consent even with a stale metadataOnly:false in config" {
  write_config '{ "platform": { "defaultTargetOrg": "sb1" }, "security": { "prodOrgAliases": [], "metadataOnly": false } }'
  seed_cache sb1 sandbox 0
  load_security_lib
  run sec_check_soql "SELECT Name FROM Account" sb1
  [ "$status" -eq 77 ]
}

@test "metadata-allowlisted SOQL is allowed by the library" {
  seed_cache sb1 sandbox 0
  load_security_lib
  run sec_check_soql "SELECT Id FROM ApexClass" sb1
  [ "$status" -eq 0 ]
}
