---
name: test-plan
description: Generate a structured test plan (positive, negative, bulk, edge, security cases) for a class, trigger, or LWC before tests are written. The plan becomes a contract @qa consumes — every case in the plan must have a corresponding test.
data-access: none
---

You are producing a **test plan** for a unit-under-test. The plan is a Markdown table @qa later turns into actual `@isTest` methods or Jest `it()` blocks. The point is to enumerate cases *before* writing tests so coverage isn't an afterthought.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
LWC_SRC="$(sf_config_get '.paths.lwcSource' "$ENV")"
COVERAGE_TARGET="$(sf_config_get '.quality.codeCoverageTarget' "$ENV")"
```

## Input

`$ARGUMENTS`: required.
- `<ApexClassName>` — produce a plan for an Apex class (or trigger)
- `<lwc-name>` — produce a plan for an LWC component
- `--out <path>` — output Markdown file (default `code-reviews/test-plans/<name>.md`)
- `--from-design` — read the latest `@architect` Test Strategy block from the conversation/clipboard and seed the plan

## Steps

### 1. Locate and read the unit under test

For Apex: `${APEX_SRC}/<ClassName>.cls` (and trigger `.trigger`)
For LWC: `${LWC_SRC}/<lwc-name>/<lwc-name>.{js,html}`

If not found, exit 2 with a clear message.

### 2. Identify the surface to test

**Apex**:
- Public/Global methods: parameters, return type
- `@AuraEnabled` methods (LWC-facing — enumerated separately; cacheable vs. write)
- `@HttpGet` / `@HttpPost` / etc. for REST services
- Trigger contexts (before/after × insert/update/delete/undelete)
- DML statements (what gets written and when)
- Callouts (what external systems are touched)
- Platform Event publishes / consumers

**LWC**:
- Public properties (`@api`)
- Public methods (`@api` methods)
- Wired adapters (Apex methods, `getRecord`, `getPicklistValues`, etc.)
- LMS subscriptions (which channels)
- Imperative Apex calls
- DOM event handlers (clicks, value changes)
- Lifecycle callbacks (`connectedCallback`, `renderedCallback`)

### 3. Enumerate cases by category

For each category, list cases. Don't be exhaustive — be representative. **One row per test method.**

| Category | What to include |
|----------|-----------------|
| **Positive** | Each happy path: minimum input, typical input, all-fields populated |
| **Negative** | `null` / blank inputs; invalid types; missing required fields; record-not-found; insufficient permissions (CRUD/FLS); SOQL no-results; DML rollback path |
| **Bulk** | 200+ records (the trigger threshold); 10K records when async/batch is in scope; verifies governor limits |
| **Edge** | Boundary values (max length strings, max precision numbers, end-of-month dates, leap years, time zones); record types; special characters; managed-package vs. unmanaged objects |
| **Security** | Sharing model: `with` vs. `without` sharing user contexts; FLS on the fields touched; SOQL injection vectors for any dynamic SOQL; OAuth flow assumptions for callouts |

### 4. For each case, specify the test contract

```
| # | Category | Description | Setup | Action | Assertion | Pattern |
|---|----------|-------------|-------|--------|-----------|---------|
| 1 | Positive | createOrder with valid payload | TestSetup: 1 Account | call createOrder(dto) | order.Id != null; order.Status = 'OPEN' | SF-15 callout mock not needed |
| 2 | Negative | createOrder with null payload | (none) | call createOrder(null) | IllegalArgumentException with message "payload required" | — |
| 3 | Bulk | persist 250 line items | TestSetup: 1 Order | persist(250 items) | all rows inserted; CPU budget OK | Test.startTest/stopTest |
| 4 | Edge | order with quantity=0 | TestSetup: 1 Order | persist 1 item qty=0 | DML error: "Quantity must be > 0" | — |
| 5 | Security | non-sharing user reads private order | TestSetup: 1 Order, owner=adminA | runAs(userB) → fetchOrder(id) | QueryException ("not found") | runAs() block |
| 6 | Callout | external 500 error | Test.setMock returning 500 | call notify() | CalloutException; error logged | SF-15 mock |
```

### 5. Output

Default Markdown:

```markdown
# Test Plan: <ClassOrLwc>

Generated: 2026-04-28T12:00:00Z (`/sf-dev-kit:test-plan`)
Coverage target: 85% (from quality.codeCoverageTarget)

## Surface
(brief enumeration of what's being tested — methods, wires, events)

## Cases
(the case table from step 4)

## Patterns referenced
- SF-15 (HTTP callout via Named Credential) — mock with Test.setMock
- SF-17 (Custom Metadata Type Lookup) — use FeatureFlags.load() in tests
- SF-14 (LWC Jest Test Structure) — for the LWC tests below
- ...

## Hand-off
@qa: implement these test methods; one per row above. Run `quality.unitTestCommand`
and `/sf-dev-kit:test-coverage <Class>` after; coverage target 85%.
```

CI mode: emit JSON (the rows from step 4 as an array of case objects). Useful when downstream tools want to validate that every row has a corresponding test method.

### 6. Exit codes
- 0 — plan emitted
- 2 — unit under test not found

## Rules

- **Plans, not tests.** Don't write Apex code or Jest test code in this skill — just the case rows
- **Reference patterns by ID.** `SF-15`, `SF-17` etc. so @qa can look them up directly
- **Keep cases atomic.** Each row → one test method. Don't bundle "positive + negative" into one row
- **Surface assumptions.** If a case depends on test data that doesn't exist (custom metadata records, perm sets), flag it in a "Test Data Required" section
- **Use the architect's Test Strategy as a starting point** when `--from-design` is passed; expand it but don't shrink it
