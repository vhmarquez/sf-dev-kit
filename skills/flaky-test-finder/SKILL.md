---
name: flaky-test-finder
description: Run a named Apex test class N times against the target org and report tests with non-deterministic results. Useful when a test fails intermittently in CI but passes locally — runs prove flakiness.
data-access: metadata-only
---

You are detecting **flaky** Apex tests by re-running them and looking for inconsistent results. A test is flaky if it passes some runs and fails others without code changes between them.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/sf-cli.sh"
sf_cli_check || exit 2
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
TEST_SUFFIX="$(sf_config_get '.naming.apex.testSuffix' "$ENV")"
```

## Input

`$ARGUMENTS`: required.
- `<TestClass>` — class to scan (e.g., `OrderServiceTest`)
- `<ProductionClass>` — production class; the skill infers `<ProductionClass><testSuffix>`
- `--runs <n>` — how many times to run (default 5)
- `--methods <m1,m2,...>` — only run specific test methods
- `--target-org <alias>` / `--env <name>` — standard overrides
- `--ci` — emit findings instead of a Markdown report

## Steps

### 1. Resolve the test class
- If `<arg>` ends in `<testSuffix>`, treat as test class directly
- Else, treat as production class and append `<testSuffix>`
- Verify the file exists in `${APEX_SRC}`

### 2. Discover test methods (if `--methods` not specified)

Grep the class for `@isTest static void <name>` patterns:
```bash
grep -E "@isTest\s+(public|private)?\s*static\s+void\s+(\w+)" "${APEX_SRC}/${TEST_CLASS}.cls" | sed -E 's/.*void (\w+).*/\1/'
```

### 3. Run each method N times

```bash
for i in $(seq 1 "$RUNS"); do
  sf apex run test --target-org "$ORG" --tests "${TEST_CLASS}.${METHOD}" --result-format json --synchronous --wait 10 > "/tmp/flaky-${TEST_CLASS}-${METHOD}-${i}.json"
done
```

`--synchronous` is important here — async runs queue and may interfere with each other.

### 4. Aggregate per method

For each method, count passes vs. fails across runs. Capture the failure messages so the user can see whether they vary.

### 5. Output

Markdown report:

```
# Flaky Test Report: <TestClass>

Org: <ORG> | Runs per method: 5

| Method                    | Pass | Fail | Verdict |
|---------------------------|------|------|---------|
| createOrder_returnsId     | 5/5  | 0/5  | ✅ stable |
| persist_handlesBulkUpdate | 3/5  | 2/5  | ⚠️ flaky |
| ...

## Flaky details

### persist_handlesBulkUpdate
Failed 2 of 5 runs. Failure messages:
- Run 2: "System.QueryException: Record not found"
- Run 4: "System.AssertException: Expected: 200, Actual: 199"

Common flakiness causes for this signature:
- Async work not flushed before assertion (missing Test.stopTest())
- Time-dependent assertions (Date.today() at midnight rollover)
- Shared state across test methods (static caches not reset)
- Order-dependent SOQL (no ORDER BY on lists asserted by index)
```

CI mode: emit one finding per flaky method:
- `ruleId: "FLAKY-TEST"`, `severity: "warning"`, file = test class file, line = method start, message includes pass/fail counts and a hint at likely cause

### 6. Exit codes
- 0 — all stable (or all failed deterministically — that's a different problem)
- 1 — at least one method is flaky (mixed pass/fail across runs)
- 2 — invocation error

## Rules

- **Run synchronously.** `--synchronous` keeps runs from interfering. Async batches queue and can deliver out of order
- **Don't auto-fix.** This skill detects; the user fixes
- **Don't mute or skip flaky tests.** Muting hides bugs. The fix is always to make the test deterministic (mock time, isolate state, use `Test.startTest`/`Test.stopTest` correctly)
- **Be quick about it.** Default 5 runs is a balance — enough to catch most flakiness, fast enough to iterate
- **Persist history.** Append the per-method pass/fail rates to `${CLAUDE_PLUGIN_DATA}/sf-dev-kit/flaky/<project>/<TestClass>.jsonl` so trends are visible across runs

## Likely causes catalog

When you flag a test as flaky, prepend the most likely cause to the report based on heuristics from the test source:

| Heuristic in test source | Likely cause |
|--------------------------|--------------|
| Calls async (`enqueueJob`, `Database.executeBatch`) without `Test.stopTest` | Missing flush boundary |
| Asserts on `Datetime.now()` or `Date.today()` against a stored value | Clock drift across runs |
| Asserts on `List<>[i]` without an `ORDER BY` in the source SOQL | Order-dependent assertion |
| Touches a static variable that other tests also touch | Shared static state |
| Reads from Custom Metadata without using `@TestVisible` loader (SF-17) | Real-org data leaking in |
| Queries Salesforce time-tracking objects (LoginHistory etc.) | Org-state-dependent |
