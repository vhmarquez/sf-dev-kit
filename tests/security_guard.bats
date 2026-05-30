#!/usr/bin/env bats
# PreToolUse Bash guard (hooks/security-guard.sh): the command-gating contract.
# exit 0 = allowed, exit 2 = blocked (with a JSON event on stderr).

load 'helpers/common'

# --- the bypasses that motivated the Phase-1 hardening (must stay blocked) ---

@test "compound ';' cannot smuggle a prod data query past a benign first verb" {
  run guard 'sf org list; sf data query --query "SELECT Name FROM Account" -o prodlisted'
  [ "$status" -eq 2 ]
  [[ "$output" == *PROD_ORG_BLOCKED* ]]
}

@test "compound '&&' cannot smuggle prod anonymous Apex" {
  run guard 'sf alias list && sf apex run --file evil.apex -o prodlisted'
  [ "$status" -eq 2 ]
}

@test "compound '||' cannot smuggle a prod delete" {
  run guard 'sf org list || sf data delete-record -s Account -i 001x -o prodlisted'
  [ "$status" -eq 2 ]
}

@test "path-qualified sf against prod is detected and blocked" {
  run guard '/usr/local/bin/sf data query --query "SELECT Id FROM Account" -o prodlisted'
  [ "$status" -eq 2 ]
}

@test "quoted sf against prod is detected and blocked" {
  run guard "'sf' data query --query \"SELECT Id FROM Account\" -o prodlisted"
  [ "$status" -eq 2 ]
}

@test "plain prod data query is blocked (baseline)" {
  run guard 'sf data query --query "SELECT Name FROM Account" -o prodlisted'
  [ "$status" -eq 2 ]
  [[ "$output" == *PROD_ORG_BLOCKED* ]]
}

# --- consent / metadata-only contract -----------------------------------------

@test "customer-data SOQL on a sandbox requires consent (blocked without token)" {
  run guard 'sf data query --query "SELECT Name FROM Account" -o sb1'
  [ "$status" -eq 2 ]
  [[ "$output" == *SOQL_DATA_OBJECT* ]]
}

@test "inline ARGO_CONSENT_GRANTED=once unblocks a sandbox data query" {
  run guard 'ARGO_CONSENT_GRANTED=once sf data query --query "SELECT Name FROM Account" -o sb1'
  [ "$status" -eq 0 ]
}

@test "metadata-allowlisted SOQL on a sandbox is allowed" {
  run guard 'sf data query --query "SELECT Id FROM ApexClass" -o sb1'
  [ "$status" -eq 0 ]
}

# --- no false positives on legitimate commands --------------------------------

@test "git piped/chained with a sandbox deploy is allowed" {
  run guard 'git status && sf project deploy start --source-dir force-app -o sb1'
  [ "$status" -eq 0 ]
}

@test "a metadata query piped to jq is allowed" {
  run guard 'sf data query --query "SELECT Id FROM Flow" -o sb1 --json | jq .'
  [ "$status" -eq 0 ]
}

@test "a command with no sf invocation is ignored" {
  run guard 'npm run build && echo done'
  [ "$status" -eq 0 ]
}

@test "sf apex run test (test execution, not anon Apex) on a sandbox is allowed" {
  run guard 'sf apex run test --tests MyTest -o sb1'
  [ "$status" -eq 0 ]
}
