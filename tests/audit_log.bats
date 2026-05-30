#!/usr/bin/env bats
# Decision/audit log (hooks/lib/security.sh): grants AND denials are recorded,
# and the log filename is keyed by full project path (no basename collisions).

load 'helpers/common'

logfile() { echo "$CLAUDE_PLUGIN_DATA"/argo/consent-log/*.jsonl; }

@test "a prod-block attempt is recorded in the decision log" {
  load_security_lib
  run sec_check_org prodlisted
  [ "$status" -eq 78 ]
  run cat $(logfile)
  [[ "$output" == *'"decision":"refused"'* ]]
  [[ "$output" == *'PROD_ORG_BLOCKED'* ]]
}

@test "a consent prompt is recorded in the decision log" {
  seed_cache sb1 sandbox 0
  load_security_lib
  run sec_check_soql "SELECT Name FROM Account" sb1
  [ "$status" -eq 77 ]
  run cat $(logfile)
  [[ "$output" == *'consent_required'* ]]
  [[ "$output" == *'SOQL_DATA_OBJECT'* ]]
}

@test "a granted data query is recorded as allow-once" {
  seed_cache sb1 sandbox 0
  load_security_lib
  export ARGO_CONSENT_GRANTED=once
  run sec_check_soql "SELECT Name FROM Account" sb1
  [ "$status" -eq 0 ]
  run cat $(logfile)
  [[ "$output" == *'allow-once'* ]]
}

@test "the decision log filename is keyed by full path, not just basename" {
  a=$(CLAUDE_PROJECT_DIR=/tmp/x/salesforce CLAUDE_PLUGIN_DATA="$TEST_TMP/d1" \
      bash -c "source '$PLUGIN_ROOT/hooks/lib/security.sh'; basename \"\$SEC_CONSENT_LOG\"")
  b=$(CLAUDE_PROJECT_DIR=/tmp/y/salesforce CLAUDE_PLUGIN_DATA="$TEST_TMP/d2" \
      bash -c "source '$PLUGIN_ROOT/hooks/lib/security.sh'; basename \"\$SEC_CONSENT_LOG\"")
  [ "$a" != "$b" ]
  [[ "$a" == salesforce-* ]]
  [[ "$b" == salesforce-* ]]
}
