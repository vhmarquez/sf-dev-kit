---
name: soql-analyzer
description: Static-analyze SOQL queries in Apex source for selectivity issues — non-selective WHERE clauses, missing indexed fields, full-table scans on LDV objects, missing LIMIT. Cross-references the org cache (when present) for actual indexed fields and row volumes.
data-access: none
---

You are analyzing SOQL queries for **selectivity**. A selective query uses an indexed field with a value that returns a small fraction of total rows; non-selective queries scan large tables and trigger query timeouts on LDV (Large Data Volume) objects. This skill flags candidate problems before they become production incidents.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
CACHE="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugin-data}/sf-dev-kit/org-cache/${ORG}.json"
```

## Indexed Fields (Salesforce-managed by default)

These fields are **always indexed** unless the query disables the index:
- `Id`
- Foreign-key (lookup / master-detail) fields
- `Name` on most standard objects
- `RecordTypeId`
- `OwnerId`
- `CreatedDate`, `LastModifiedDate`, `SystemModstamp`
- `External Id` and `Unique` custom fields
- Custom fields explicitly indexed (custom indexes — visible only via the org cache, not source)

Non-indexed by default:
- Other custom fields (`Status__c`, `Region__c`, etc.)
- `Description`, `Body`, long text areas

## Selectivity Rules

| Filter pattern | Selective? |
|----------------|------------|
| `Id = :var` or `Id IN :ids` | ✅ always |
| `<Lookup>__c = :var` | ✅ if cardinality is reasonable |
| `<Indexed> = :var` | ✅ |
| `<NonIndexed> = :var` (small object, < 10K rows) | ✅ acceptable |
| `<NonIndexed> = :var` (LDV object, > 1M rows) | ❌ non-selective; needs index or different approach |
| `LIKE '%value'` (leading wildcard) | ❌ never uses index |
| `LIKE 'value%'` (trailing wildcard) | ✅ uses index if field is indexed |
| `NOT IN`, `!=` | ❌ generally non-selective |
| `<NULL> = NULL` | ❌ NULL doesn't index |
| Multi-`OR` across non-indexed fields | ❌ |

## Input

`$ARGUMENTS`:
- (empty) — analyze all `.cls` and `.trigger` files
- `<ClassName>` — analyze a single class
- `--ldv-threshold <rows>` — flag any object with > N rows in the org cache as LDV (default `1000000`)
- `--target-org <alias>` / `--env <name>` — for live cardinality / index lookup
- `--ci` / `--format json|sarif` / `--out <path>`

## Steps

### 1. Walk the Apex source

For each file, find SOQL statements:
```regex
\[\s*SELECT\s+(.+?)\s+FROM\s+(\w+)(?:\s+(?:USING\s+SCOPE\s+\w+)?\s*WHERE\s+(.+?))?(?:\s+ORDER\s+BY\s+(.+?))?(?:\s+LIMIT\s+(\d+))?\s*\]
```

Multi-line / dynamic SOQL via `Database.query`: capture the string literal portion; if dynamic, flag for manual review.

### 2. Parse each WHERE clause

For each predicate:
- Identify the field
- Identify the operator
- Identify the right-hand value (literal, bind variable, dynamic)

### 3. Classify the query

For the FROM object:
- Look up in the org cache: actual indexed fields (custom-indexed flag), row count if available
- Map predicates against the indexed/non-indexed table above

Findings:
| Issue | Severity | Rule ID |
|-------|----------|---------|
| Query has no WHERE clause on a custom or sensitive standard object | error | `SOQL-NO-WHERE` |
| WHERE filters on only non-indexed fields, FROM is custom or LDV-flagged object | warning | `SOQL-NON-SELECTIVE` |
| Leading `%` in LIKE | warning | `SOQL-LIKE-LEADING-WILDCARD` |
| `NOT IN` or `!=` as primary filter | warning | `SOQL-NEGATIVE-FILTER` |
| No `LIMIT` and FROM is LDV | warning | `SOQL-NO-LIMIT-LDV` |
| `ORDER BY` on non-indexed field with no LIMIT | warning | `SOQL-ORDER-BY-NON-INDEXED` |
| Dynamic SOQL — string concatenation builds WHERE | note | `SOQL-DYNAMIC` (pair with /security-scan for SOQL injection check) |

### 4. Output

Default Markdown:
```
# SOQL Analysis: <project.name>

Apex files scanned: 47 | Queries found: 124
LDV threshold: 1,000,000 rows
Org cache: <CLAUDE_PLUGIN_DATA>/.../DevVM.json (cachedAt: 2026-04-28T12:30:00Z)

## Findings

### Critical (3)
- `force-app/.../OrderReportController.cls:42` — `[SELECT ... FROM Order__c]` (no WHERE) — Order__c has 2.4M rows
- ...

### High (5)
- `force-app/.../SearchService.cls:18` — `[SELECT Id FROM Account WHERE Description LIKE '%...']` — leading wildcard, full scan
- `force-app/.../UnusedJob.cls:55` — `[SELECT ... FROM Lead]` (no LIMIT) on LDV
- ...

### Medium (8)
- `force-app/.../StatusBatch.cls:30` — `[SELECT ... FROM Order__c WHERE Status__c = :s]` — Status__c not indexed; consider custom index or external archive

### Notes (2)
- `force-app/.../DynamicReportController.cls:88` — Dynamic SOQL (Database.query) — manual review needed
```

CI mode: SARIF emit per finding.

### 5. Exit codes
- 0 — no error/warning findings
- 1 — any finding
- 2 — config error / no Apex source

## Rules

- **Heuristic, not perfect.** Apex parsing without an AST is approximate. Mark dynamic SOQL as a note and let the human inspect
- **Honor the org cache.** If `${CACHE}` lists a custom index on `Status__c`, don't flag `WHERE Status__c =` as non-selective. Run `/sf-dev-kit:org-explore --refresh` to update
- **Don't flag tests.** `*<testSuffix>.cls` is excluded by default
- **Cross-link to fixes.** Each finding's message should mention the appropriate fix: "add a custom index" / "filter by Id or lookup field" / "consider archiving" / "convert to a paginated report"

## Consumers

- `/sf-dev-kit:code-review` consumes the JSON output and rolls up into the review report
- `@architect` and `@data-architect` reference the report when designing new query paths
