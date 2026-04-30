---
name: dead-code
description: Find unused code in the project — Apex methods/fields with no references, LWC components never imported anywhere, custom labels never used in source, custom permissions never checked, and orphan flow elements. Reports candidates for deletion (the user decides).
data-access: none
---

You are scanning for **unreferenced code**. Findings are *candidates for deletion* — the user reviews and decides. Some matches are false positives (reflection, dynamic SOQL, deserialization), so the report errs toward conservative reporting.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
LWC_SRC="$(sf_config_get '.paths.lwcSource' "$ENV")"
TEST_SUFFIX="$(sf_config_get '.naming.apex.testSuffix' "$ENV")"
```

## Input

`$ARGUMENTS`:
- (empty) — full scan
- `apex` — Apex methods/fields only
- `lwc` — LWC components only
- `labels` — custom labels only
- `--ci` / `--format json|sarif` / `--out <path>`

## Steps

### 1. Apex unused methods

For each `public`/`global` method (not test methods, not `@AuraEnabled`):
- Find references: `<ClassName>\.<method>\b` and `<method>\(` from within the same class
- Trigger handler methods (`beforeInsert`, etc.) are entry points — exclude
- `execute(QueueableContext)`, `execute(BatchableContext, ...)`, `start`, `finish` — async entry points; exclude
- `@RemoteAction`, `@HttpGet`, etc. — REST entry points; exclude
- If no references found anywhere in source → finding `DEAD-METHOD`

### 2. Apex unused fields

For each `public`/`private` instance/static field on a class:
- Find references: `\.<fieldName>\b` and `<fieldName>\b` within the class
- `@AuraEnabled` fields on DTOs — entry points; exclude
- If no references → finding `DEAD-FIELD`

### 3. LWC unused components

For each LWC bundle in `${LWC_SRC}`:
- Search for `c-<kebab-case>` in HTML files (other LWCs)
- Search for `from 'c/<camelCase>'` in JS files
- If `js-meta.xml` has `<isExposed>true</isExposed>`, the component might be referenced from an Experience Cloud / Lightning page builder — it's an **entry point** (don't flag)
- If unexposed and unreferenced → finding `DEAD-LWC`

### 4. Custom labels

```bash
find force-app -name '*.labels-meta.xml' -exec ...
```
For each `<fullName>` in custom labels XML, search source for:
- Apex: `System.Label.<Name>` and `Label.<Name>`
- LWC JS: `import X from '@salesforce/label/c.<Name>'`
- Layouts/Flows: `<Name>` value references

If nothing matches → finding `DEAD-LABEL`.

### 5. Custom permissions

For each `<CustomPermission>` defined:
- Search Apex for `FeatureManagement.checkPermission('<DeveloperName>')` and `Schema.SObjectType.<...>.PermissionsChecked`
- Search LWC for `import HAS_PERM from '@salesforce/customPermission/<DeveloperName>'`
- If nothing → finding `DEAD-CUSTOM-PERM`

### 6. Orphan flow elements

For each `force-app/**/flows/*.flow-meta.xml`:
- Parse the XML structurally and look for elements (decisions, assignments) that are not connected to any path from the start element
- If found → finding `DEAD-FLOW-ELEMENT` (one per element, with element name)

This is heuristic — flow connector parsing is complex; flag for human review.

## Output

Default Markdown:
```
# Dead Code Report: <project.name>

Apex files scanned: 47 (production)
LWC bundles scanned: 18 (in-scope)
Custom labels: 142
Run at: 2026-04-28T15:00:00Z

## Findings

### High (likely dead — review and delete)
- `DEAD-METHOD` `OrderHelper.legacyComputeTotal()` — no references in 47 production files (force-app/.../OrderHelper.cls:120)
- `DEAD-LWC` `acmeOldDashboard` — bundle has 1.2K of code, isExposed=false, never imported
- ...

### Medium (probably dead — investigate)
- `DEAD-LABEL` `c.Old_Welcome_Banner` — defined in CustomLabels.labels-meta.xml, unused in source
- `DEAD-CUSTOM-PERM` `Manage_Legacy_System` — never checked in source
- ...

### Low (suspicious — false-positive risk)
- `DEAD-METHOD` `OrderApiClient.serializeForExternal()` — only string-referenced via `JSON.deserialize`; this scan can't detect dynamic invocation. Confirm before deleting

## Caveats
- Reflection, dynamic Apex (`Type.forName`), and deserialization can reference symbols this scan misses. **Always grep for the symbol as a string** before deleting (the report does this automatically for medium/low confidence)
- Apex methods exposed via REST/SOAP that aren't called from source may still have external consumers
- LWCs referenced only from Lightning App Builder pages won't appear in source; verify in the org before deleting
```

CI mode: SARIF emit per finding with the appropriate `ruleId`.

## Exit codes
- 0 — no findings
- 1 — any finding (informational; this skill never blocks merges by default)
- 2 — config error

## Rules

- **Bias toward false positives in the medium/low buckets.** Hidden references via reflection / deserialization are real; the user must verify
- **Don't auto-delete.** This is a report. The user runs `/argo:destructive-changes add ...` if they want to remove items
- **Skip test classes for "unused method" finding.** Test methods are entry points by definition (run by the test runner)
- **Honor custom annotations.** `@AuraEnabled`, `@HttpGet`/etc., `@InvocableMethod`, `@RemoteAction`, `@future`, `@Schedulable`, `@Database.Batchable`, `@TestVisible` — all are entry-point markers
- **Cross-link to /destructive-changes.** The next step after dead-code review is usually destructive-changes
