---
name: test-coverage
description: Run Apex code coverage or agent evaluation tests against the project's default org. Two modes — `apex` (default; deploys + runs Apex tests with coverage) and `agent` (delegates to /argo:agent-test for Agentforce eval suites).
data-access: metadata-only
---

You are running test coverage for this project. Two modes:

- **`apex`** (default) — deploy + run Apex tests + report coverage; appends to coverage history for `/coverage-trend`
- **`agent`** — delegate to `/argo:agent-test`; appends to agent-eval history for `/agent-eval-trend`

Mode is selected by the first positional argument: `apex` (or `apex <ClassName>`) vs. `agent` (or `agent <agent-name>`). When the first argument is a class name (no `apex`/`agent` prefix), Apex mode is assumed for backwards compatibility with v1.

Always target the org configured in `.claude/sf-project.json`.

## Read Project Config First

Always start by reading `.claude/sf-project.json`:
- `platform.defaultTargetOrg` — the org alias to test against unless the user specifies otherwise
- `paths.apexSource` — base directory for class lookups
- `naming.apex.testSuffix` — used to derive test class names from production class names (default: `Test`)
- `quality.codeCoverageTarget` — coverage threshold to enforce (default: 85%)

## Input

The user provided: `$ARGUMENTS`

This could be:
- `apex <ClassName>` — Apex mode: a test class or production class name (infer test by appending `naming.apex.testSuffix`)
- `apex all` — run every Apex test class
- `agent <agent-name>` — agent mode: dispatch to `/argo:agent-test <agent-name>`
- `agent all` — dispatch to `/argo:agent-test` (full eval suite run)
- `<ClassName>` (legacy) — equivalent to `apex <ClassName>`
- An override `--target-org <alias>` — use a different org instead of `platform.defaultTargetOrg`
- An override `--env <name>` — load `.claude/sf-project.<name>.json` overrides
- Empty — prompt the user to specify a mode + target

In agent mode, this skill is a thin dispatcher to `/argo:agent-test`; all agent-specific options (`--fail-on`, `--suite`, etc.) pass through.

CI flags (per `${CLAUDE_PLUGIN_ROOT}/docs/ci-output-contract.md`):
- `--ci` — machine-readable output, exit codes per contract
- `--format json|sarif` — output format (default `json` in CI mode)
- `--out <path>` — write to file instead of stdout

In CI mode, after running tests, also append the result to `${CLAUDE_PLUGIN_DATA}/argo/coverage/<project>/history.jsonl` so `/argo:coverage-trend` can show the trend later.

## Steps

1. **Resolve the test class and its production class.**
   - If given a production class name, the test class is `{ClassName}{naming.apex.testSuffix}`
   - If given a test class name, the production class is the name with the suffix stripped
   - Verify both files exist in `{paths.apexSource}`
   - If `all` is specified, skip to step 3 with `--test-level RunLocalTests` instead of `--class-names`

2. **Deploy the classes.** Substitute `<org>` with `platform.defaultTargetOrg` (or the user's override):
   ```
   sf project deploy start --target-org <org> --source-dir {paths.apexSource}/{ProductionClass}.cls --source-dir {paths.apexSource}/{TestClass}.cls --wait 10
   ```
   - If the deploy fails, report the error and stop
   - If `all`, deploy the full project: `sf project deploy start --target-org <org> --wait 10`

3. **Run the tests with code coverage.**
   ```
   sf apex run test --class-names {TestClass} --code-coverage --result-format human --target-org <org> --wait 10
   ```
   - If `all`: `sf apex run test --test-level RunLocalTests --code-coverage --result-format human --target-org <org> --wait 15`

4. **Report the results.** Summarize:
   - Total tests / passed / failed
   - Any failed test names with their error messages
   - Coverage percentage for the production class
   - Uncovered lines (if any)
   - Whether it meets the project target from `quality.codeCoverageTarget`

## CI Mode

In CI mode emit findings shaped like:
```json
[
  {
    "ruleId":  "COV-BELOW-TARGET",
    "severity": "error",
    "message": "OrderApiClient coverage 63.3% below target 85%",
    "file":    "force-app/main/default/classes/OrderApiClient.cls",
    "line":    1,
    "tool":    "test-coverage"
  }
]
```

Exit codes:
- 0 — all tests passed; coverage at or above `quality.codeCoverageTarget`
- 1 — any test failed, or any class below target
- 2 — deploy or test-run failure

For SARIF output, source `${CLAUDE_PLUGIN_ROOT}/hooks/lib/sarif.sh` and pipe through `sarif_emit "argo/test-coverage" "<plugin-version>"`.

## Rules

- **Default to `platform.defaultTargetOrg` from config** — never change orgs unless the user explicitly specifies one
- Always deploy before running tests to ensure the org has the latest code
- If tests fail, show the failure messages clearly — do not re-run automatically
- If coverage is below `quality.codeCoverageTarget`, flag it and list the uncovered lines
