---
name: fls-audit
description: Static-analyze Apex source for DML and SOQL operations missing CRUD/FLS enforcement. Reports every `insert`/`update`/`delete`/`upsert`/`merge` and dynamic SOQL that doesn't use USER_MODE / SECURITY_ENFORCED / Schema.DescribeSObjectResult checks.
---

You are auditing **CRUD and Field-Level Security (FLS)** enforcement in Apex. Modern Salesforce orgs require `WITH USER_MODE` (or `WITH SECURITY_ENFORCED`) on SOQL and `as user` on DML, or explicit `Schema.sObjectType.Foo.fields.bar.isAccessible()` checks. This skill flags places where those guards are missing.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
TEST_SUFFIX="$(sf_config_get '.naming.apex.testSuffix' "$ENV")"
SHARING_DEFAULT="$(sf_config_get '.platform.sharingDefault' "$ENV")"
```

## Input

`$ARGUMENTS`:
- (empty) — audit all production Apex (skip test classes)
- `<ClassName>` — audit one class
- `--include-tests` — include test classes (rarely useful — test code intentionally bypasses FLS)
- `--ci` / `--format json|sarif` / `--out <path>`

## Steps

### 1. Walk Apex files

For each `.cls` and `.trigger` in `${APEX_SRC}`:
- Skip test classes unless `--include-tests`
- Read the file content

### 2. Identify DML statements

Pattern (Apex source is straightforward to scan with regex; full AST is overkill):
```regex
\b(insert|update|upsert|delete|merge)\s+(?!as\s+(user|system))(?!\bnew\b)\s*([A-Za-z_][\w.]*)
```

For each match:
- Capture the verb (`insert`, `update`, etc.) and the variable / record being touched
- Look for `as user` or `as system` qualifier
- If neither, this is a candidate finding

### 3. Identify SOQL statements

Pattern:
```regex
\[\s*SELECT\s+(.+?)\s+FROM\s+(\w+)
```

For each match:
- Capture the SELECT clause and FROM target
- Search the same statement for `WITH USER_MODE` or `WITH SECURITY_ENFORCED`
- If neither, candidate finding

### 4. Identify dynamic SOQL

```regex
\bDatabase\.(query|getQueryLocator)\s*\(
```

For each match:
- Inspect the query string composition (look for string concatenation up to N lines back)
- If the query string is built from variables and the call doesn't include `with AccessLevel.USER_MODE`, candidate finding

### 5. Identify Database.* DML

```regex
\bDatabase\.(insert|update|upsert|delete|merge)\s*\(
```

Look for `, AccessLevel.USER_MODE` or `, true /*allOrNothing*/, AccessLevel.USER_MODE` parameter.

### 6. Filter and classify

| Heuristic | Severity | Rule ID |
|-----------|----------|---------|
| DML without `as user`/`as system`/`AccessLevel.USER_MODE` | error | `FLS-DML-NO-CHECK` |
| Static SOQL without `WITH USER_MODE` and FROM is custom or sensitive standard object (Account/Contact/Case/User/Lead/Opportunity) | warning | `FLS-SOQL-NO-CHECK` |
| Dynamic SOQL via `Database.query` without `AccessLevel.USER_MODE` | error | `FLS-DYNAMIC-SOQL-NO-CHECK` |
| Class declared `without sharing` | warning | `FLS-WITHOUT-SHARING` (cross-link to /sharing-review) |

Skip if the line contains a leading comment with `// fls-audit:disable` (suppression).

### 7. Output

Default Markdown:
```
# FLS Audit: <project.name>

Apex classes scanned: 47 (production, excluding tests)
Sharing default: with sharing
Run at: 2026-04-28T13:00:00Z

## Findings

### Critical (DML without enforcement) — 3
- `force-app/.../OrderService.cls:84` — `insert order;`  (use `insert as user order;`)
- `force-app/.../OrderApiClient.cls:121` — `update updates;`  (use `update as user updates;`)
- ...

### Critical (Dynamic SOQL without enforcement) — 1
- `force-app/.../SearchController.cls:42` — `Database.query(soql)` — pass `AccessLevel.USER_MODE`

### High (Static SOQL on sensitive object without enforcement) — 4
- `force-app/.../AccountReader.cls:18` — `[SELECT Id, Name FROM Account WHERE ...]` — add `WITH USER_MODE`
- ...

## Suppressions in source
- `force-app/.../SystemAdminQueue.cls:55` — `// fls-audit:disable` (justified: scheduled job runs as system)

## How to fix
- DML: append `as user` for caller-context, `as system` for elevated context (justify in comment)
- Static SOQL: append `WITH USER_MODE` to the query
- Dynamic SOQL: pass `with AccessLevel.USER_MODE` as the second arg to `Database.query`
- Manual checks: `Schema.sObjectType.Foo.fields.Bar.isAccessible()` before reading custom-extracted fields
```

CI mode: emit findings via `sarif_emit "sf-dev-kit/fls-audit" "$VERSION"`.

### 8. Exit codes
- 0 — no error-level findings
- 1 — any error
- 2 — file-not-found / config error

## Rules

- **Static analysis only.** No org queries; no PMD dependency
- **Don't double-fire with /security-scan.** PMD's `ApexCRUDViolation` covers some of this. The skills overlap intentionally — both will catch DML issues; this skill adds dynamic-SOQL specifics. CI pipelines should run both
- **Honor sharing context.** A class that's `without sharing` is reported as a finding here too (cross-linked to `/sharing-review`)
- **Suppressions need justification.** `// fls-audit:disable` is allowed but the line should also have a `// reason: ...` comment within 3 lines. If missing, downgrade to a warning telling the user to justify
- **Don't audit test classes** unless `--include-tests` is passed — they're allowed to bypass FLS
