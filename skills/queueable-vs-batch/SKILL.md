---
name: queueable-vs-batch
description: Decide between Queueable Apex, Batch Apex, Schedulable, and `@future` for an async piece of work. Asks 5–6 quick questions, then recommends with rationale.
data-access: none
---

You are picking the right async mechanism. Salesforce offers four+ kinds; each has different governor limits, scheduling semantics, and chaining rules.

## Decision questions

1. **How many records is the unit of work?** under 50, 50–10K, 10K–50M, > 50M?
2. **Is it triggered by a timer / cron, by a record event, or by user action?**
3. **Does it need to chain into another async job afterward?**
4. **Does it call external systems (callouts)?**
5. **Does it need transaction integrity across the whole job, or per-chunk?**
6. **Does it need to run on a schedule (every hour, every night)?**

## Decision tree

```
< 50 records, fire-and-forget, no chaining, no state
  → @future — simplest; one method invocation per call; deprecated for new work but still valid

< 50 records, may need to chain, keep state across runs, callout
  → Queueable (with Database.AllowsCallouts if calling out)

50 – 10K records, chunk-able, runs in single transaction per chunk
  → Database.Batchable — one start/execute/finish; chunk size up to 2000

10K – 50M records, very large or needs scheduling
  → Database.Batchable + Schedulable wrapper; consider chunking by date/owner key

External event consumer, throughput-oriented
  → Platform Event subscriber (see pattern-pack add platform-events) — not Batch

User clicks a button → "Do work in background"
  → Queueable enqueued from the LWC's Apex controller; static guard to prevent duplicate enqueues (PRJ-6)

Periodic ETL / nightly recompute
  → Database.Batchable invoked from a Schedulable (System.schedule)
```

## Limits matrix (single-record async)

| Mechanism | SOQL | DML | Heap | CPU | Callouts | Concurrency |
|-----------|------|-----|------|-----|----------|-------------|
| `@future` | 200 | 150 | 12 MB | 60s | 10 | 50/hr |
| `Queueable` | 200 | 150 | 12 MB | 60s | 10 | 50 enqueues/tx; chain unlimited |
| `Database.Batchable` (per execute) | 200 | 150 | 12 MB | 60s | 10 | scope ≤ 2000 records |
| `Schedulable` | depends — usually wraps Batch | — | — | — | — | scheduled jobs limited org-wide |

## Output

```
# Async Choice

## Description
Recompute customer-rank rolls-up across all Accounts nightly (~250K Account rows)

## Answers
- Volume:          250K records
- Trigger:         scheduled (nightly)
- Chains:          no
- Callouts:        no
- Transaction:     per-chunk OK
- Schedule:        every night at 02:00

## Recommendation: **Database.Batchable + Schedulable wrapper**

### Why
- 250K rows — far above Queueable's 12 MB heap if loaded in one shot. Batch chunks (default 200, configurable up to 2000) keep heap manageable
- Per-execute transaction is fine — failure of one chunk doesn't void earlier chunks
- Native scheduling via `System.schedule(name, '0 0 2 * * ?', new Schedulable_Wrapper())`
- No callouts → no need for `Database.AllowsCallouts`

### Implementation outline
- `AccountRankBatch implements Database.Batchable<sObject>`
  - `start(BatchableContext)` returns the iterator (typically `Database.QueryLocator` for SOQL-defined scope)
  - `execute(BatchableContext, List<sObject> scope)` does the per-chunk work
  - `finish(BatchableContext)` logs summary and optionally chains to next job
- `AccountRankSchedulable implements Schedulable`
  - `execute(SchedulableContext)` calls `Database.executeBatch(new AccountRankBatch(), 200);`
- Schedule once via Setup or anonymous Apex:
  ```apex
  System.schedule('Nightly Account Rank', '0 0 2 * * ?', new AccountRankSchedulable());
  ```

### Patterns referenced
- SF-7 (Trigger Handler Framework — not relevant here, but consider if you also have a record-triggered path)
- PRJ-6 (Queueable with Static Guard — not relevant for Batch but mentioned for completeness)

### Alternatives considered
- **Queueable chain**: would work but burns 50 enqueues per cycle and the per-job 12 MB heap forces tiny chunks; Batch is cleaner
- **`@future`**: doesn't chain, no scope, no progress tracking; not appropriate for 250K rows
```

## Rules

- **Don't recommend `@future` for new work.** It's still supported but lacks chaining, state, and observability. Queueable is the modern equivalent
- **Batch's `start` query result counts toward the 50 million row limit.** For >50M rows, partition by date/owner/region and use a `Database.QueryLocator` per slice
- **If callouts are needed, enable them.** `Queueable + implements Database.AllowsCallouts` or `Batchable + implements Database.AllowsCallouts`
- **Static guards (PRJ-6) prevent duplicate enqueues from triggers.** Always recommend when the queueable is invoked from a record trigger
