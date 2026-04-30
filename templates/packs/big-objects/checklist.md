### Big Objects
- [ ] Index fields chosen to match the queries you actually need (BIG-1) — list those queries before writing the index
- [ ] All writes go through `Database.insertImmediate` or Bulk API 2.0 — never standard `insert` DML (BIG-2)
- [ ] No deletable / GDPR-eligible data is stored in a Big Object (no row-level delete API)
- [ ] Wide / aggregating queries use Async SOQL with a target rollup sObject (BIG-3); UIs read from the rollup, never the Big Object directly
- [ ] All sync SOQL predicates filter on the leading index field with `=` or `IN`; range only on the last bound index field (BIG-4)
- [ ] Capacity tier purchased and `Database.countQuery` monitored on a recurring cadence (BIG-5)
- [ ] Decommission path rehearsed in a sandbox at the production row-count tier
