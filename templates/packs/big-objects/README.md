# Big Objects Pack

Patterns for **Big Objects** — Salesforce's append-only, billions-of-rows storage tier outside the standard data model. Used for archival, audit history, IoT telemetry, and other high-volume, immutable data shapes.

## When to use this pack

Install with `/argo:pattern-pack add big-objects` if your project:
- Captures audit / change-history data that would blow standard storage limits
- Stores append-only event records (telemetry, signals, log-style data)
- Archives standard-object records past retention into queryable cold storage
- Runs analytical aggregations across billions of rows (Async SOQL)

Don't install for:
- Transactional data (Big Objects are eventually-consistent and have no triggers)
- Data subject to row-level delete (GDPR right-to-be-forgotten) — Big Objects are append-only
- General-purpose CRUD use cases — use standard objects

## What's in the pack

- **BIG-1: Defining a Big Object** — metadata, picking the index, immutability of the index
- **BIG-2: Inserting via Apex (Bulk-Safe)** — `Database.insertImmediate`, Queueable chunking, Bulk API 2.0
- **BIG-3: Async SOQL for Aggregation** — analytical queries that write results to a rollup sObject
- **BIG-4: Querying with Index-Aligned Predicates** — the SOQL constraints sync queries must follow
- **BIG-5: Lifecycle and Capacity Planning** — tier sizing, retention buckets, decommission paths

Plus checklist items covering write-mode safety, query predicate alignment, capacity monitoring, and decommission rehearsal.

## What's not in the pack

- The archival mover itself (S3 / GCS / lakehouse export) — that's project infra, not a Salesforce pattern
- Standard-object archival via `Database.delete` — covered indirectly via BIG-5's "what to archive" decision

## Cross-references

- Related pack: `change-data-capture` — common ingest path into a Big Object (subscribe to CDC, write to BIG)
- Base patterns: SF-7 (Trigger Handler), SF-9 (Wrapper / DTO Classes — for Async SOQL rollup payloads)
- Specialist agents: `@data-architect` for index design, `@apex-dev` for the writer/queryer

## References

- [Big Objects Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.bigobjects.meta/bigobjects/)
- [Async SOQL Reference](https://developer.salesforce.com/docs/atlas.en-us.bigobjects.meta/bigobjects/async_soql.htm)
- [`Database.insertImmediate`](https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_methods_system_database_immediate.htm)
