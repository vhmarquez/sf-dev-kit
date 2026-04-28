---
name: limit-usage
description: Static estimate of governor-limit consumption per public Apex method — count of SOQL queries, DML statements, callouts, queries-in-loops, async enqueues. Useful for spotting bulk-unsafe code before runtime.
---

You are estimating **governor-limit usage** per Apex method. The estimates are static and conservative — they count operations textually without simulating runtime branches. The output points to methods worth bulk-load testing.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
TEST_SUFFIX="$(sf_config_get '.naming.apex.testSuffix' "$ENV")"
```

## Limits Reference

| Limit | Sync | Async |
|-------|------|-------|
| SOQL queries | 100 | 200 |
| DML statements | 150 | 150 |
| Records retrieved | 50,000 | 50,000 |
| Heap | 6 MB | 12 MB |
| CPU time | 10,000 ms | 60,000 ms |
| Callouts | 100 | 100 |
| Future calls | 50 | 0 |
| Queueable enqueues | 50 | 1 |

## Input

`$ARGUMENTS`:
- (empty) — analyze all production Apex
- `<ClassName>` — analyze a single class
- `--threshold-soql <n>` — flag methods with > N SOQL statements (default 5)
- `--threshold-dml <n>` — flag methods with > N DML statements (default 5)
- `--ci` / `--format json|sarif` / `--out <path>`

## Steps

### 1. Per-method counters

For each method (public/private/global/static), count occurrences of:
- SOQL: `\[\s*SELECT` and `Database\.query|Database\.getQueryLocator`
- DML: bare `insert|update|upsert|delete|merge` keywords + `Database\.(insert|update|...)`
- Callouts: `\bnew Http\(\)\.send|HttpRequest`
- Future: `@future` annotation on the method itself
- Queueable: `System\.enqueueJob`
- Email: `Messaging\.sendEmail`
- Platform Event publish: `EventBus\.publish`

### 2. Detect SOQL/DML inside loops

For each loop construct (`for`, `while`, `do`):
- If the loop body contains a SOQL or DML statement → finding `LIMIT-LOOP-DML` (error) / `LIMIT-LOOP-SOQL` (error)
- If the loop body calls a method that has SOQL/DML — note (recursive resolution is approximate; flag as "possible")

### 3. Detect missing static guard on async

For Queueable / `@future` / Schedulable methods:
- Look for a static Boolean guard pattern (PRJ-6 in project-patterns.md)
- If absent → finding `LIMIT-ASYNC-NO-GUARD` (warning)

### 4. Output

Default Markdown:
```
# Governor-Limit Usage: <project.name>

Apex files scanned: 47 (production)
Run at: 2026-04-28T13:45:00Z

## Per-method summary (top 10 by SOQL count)

| Class.Method | SOQL | DML | Callouts | Async | Notes |
|--------------|------|-----|----------|-------|-------|
| OrderService.persist | 4 | 3 | 0 | 0 | bulk-safe |
| ReportBuilder.run | 12 | 0 | 0 | 0 | ⚠️ many SOQL; consider single query |
| OrderApiClient.fetchAll | 1 | 0 | 1 | 0 | callout in sync method |
| ...

## Findings

### Critical
- `LIMIT-LOOP-DML` — `BatchSyncJob.processChunk` line 88 has DML inside a `for` loop (10 records → 10 DML statements; 200 records → governor limit hit)
- ...

### High
- `LIMIT-LOOP-SOQL` — `LegacyImporter.importBatch` line 42 has SOQL inside a `for` loop
- ...

### Medium
- `LIMIT-MANY-SOQL` — `ReportBuilder.run` issues 12 SOQL statements per call; consider a single query with sub-selects
- ...

### Warnings
- `LIMIT-ASYNC-NO-GUARD` — `OrderUpdateQueueable.execute` has no static Boolean guard (PRJ-6); duplicate enqueues from triggers will run multiple times
- ...
```

CI: SARIF emission per finding.

### 5. Exit codes
- 0 — no error/warning findings
- 1 — any finding
- 2 — config error

## Rules

- **Static counts are conservative.** A method with 5 SOQL statements may run only 1–2 at runtime depending on branches. Treat counts as upper bounds
- **Loop detection is heuristic.** Reasonable accuracy for `for/while/do` blocks; not for recursion. Don't crash on edge cases — flag as "possible"
- **Cross-class call resolution is approximate.** When method A calls method B and B has SOQL, A's effective count includes B's. Mark these as "transitive" in the per-method table
- **Honor the async distinction.** Queueable / Batch methods are async; their thresholds are higher. Detect via `Database.Stateful`/`Queueable`/`Schedulable`/`Database.Batchable`/`@future` and apply the async limit table

## Consumers

- `@architect` consumes the per-method summary when planning the "Governor Limit Budget" section of a design
- `/sf-dev-kit:code-review` rolls findings into the High/Medium severity sections
