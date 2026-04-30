---
name: field-impact
description: Find all references to a Salesforce field across LWC, Apex, layouts, validation rules, formula fields, Flows, and reports. Use before deleting or renaming a field, or when assessing the blast radius of a field-level change.
data-access: metadata-only
---

You are computing the **blast radius** for a field change. The user asks "who depends on `Account.Custom_Field__c`?" and you answer with a structured report grouped by metadata type.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/sf-cli.sh"
LWC_SRC="$(sf_config_get '.paths.lwcSource' "$ENV")"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
```

## Input

`$ARGUMENTS`: required.
- `<Object>.<Field>` — full reference (e.g., `Account.Risk_Score__c`)
- `<Field>` — bare field; the skill greps without object qualifier (less precise)
- `--target-org <alias>` / `--env <name>` — for org-side checks (formula references, etc.)
- `--ci` / `--format json|sarif` / `--out <path>`

## Steps

### 1. Validate the field exists (if `--target-org`/cache available)
- Read `${CLAUDE_PLUGIN_DATA}/sf-dev-kit/org-cache/<org>.json` if present
- If absent, run `sf_cli_describe <Object> <ORG>` and extract field list
- If the field doesn't exist, warn but continue with source-only search

### 2. Search source by metadata type

For each metadata type, define a search and capture file + line + snippet. Use `Grep` (ripgrep-backed) for speed.

| Metadata | Pattern | Path glob |
|----------|---------|-----------|
| Apex     | `\.<Field>\b` and `'<Field>'` (string) | `{paths.apexSource}/**/*.cls`, `**/*.trigger` |
| LWC JS   | `<Field>` (within `fields:` arrays, string queries, template selectors) | `{paths.lwcSource}/**/*.js` |
| LWC HTML | `record\.fields\.<Field>` | `{paths.lwcSource}/**/*.html` |
| Page Layouts | `<fullName>.*\.<Field></fullName>` | `force-app/**/layouts/*.layout-meta.xml` |
| Validation Rules | `<Field>` in `<errorConditionFormula>` or `<formula>` | `force-app/**/objects/<Object>/validationRules/*.validationRule-meta.xml` |
| Formula Fields | `<formula>` containing `<Field>` | `force-app/**/objects/<Object>/fields/*.field-meta.xml` |
| Flows | `<elementReference>` containing `<Field>` | `force-app/**/flows/*.flow-meta.xml` |
| Reports | `<column>` or `<filter>` containing `<Field>` | `force-app/**/reports/**/*.report-meta.xml` |
| Email Templates | `{!<Object>.<Field>}` | `force-app/**/email/**/*.email-meta.xml` |
| Permission Sets | `<field>...<Field></field>` | `force-app/**/permissionsets/*.permissionset-meta.xml` |
| Profiles | `<field>...<Field></field>` | `force-app/**/profiles/*.profile-meta.xml` |
| Custom Metadata | `<Field>` value references | `force-app/**/customMetadata/*.md-meta.xml` |

For the bare `<Field>` form (no object qualifier), prefix matches with the object name to reduce false positives — but warn the user that some references may be missed if the field is referenced as a string.

### 3. Org-side queries (optional, if `--target-org`)

```bash
# Formula fields on OTHER objects that reference this field
sf data query --target-org "$ORG" --json --query "
  SELECT EntityDefinition.QualifiedApiName, QualifiedApiName, FormulaDescription
  FROM FieldDefinition
  WHERE FormulaDescription LIKE '%<Object>.<Field>%'
"

# Flow definitions referencing this field (best-effort; relies on flow XML being in source)
# (skipped — covered by source search)
```

### 4. Output

Default Markdown:
```
# Field Impact: Account.Risk_Score__c

Run at: 2026-04-28T11:00:00Z
Field exists in target org: ✅ (custom number, length 18, scale 2)
Total references: 17

## Apex (5)
- `force-app/main/default/classes/AccountController.cls:42` — `acct.Risk_Score__c`
- ...

## LWC JS (3)
- `force-app/main/default/lwc/acmeAcctRisk/acmeAcctRisk.js:12` — `'Account.Risk_Score__c'`
- ...

## LWC HTML (1)
- `force-app/main/default/lwc/acmeAcctRisk/acmeAcctRisk.html:8` — `record.fields.Risk_Score__c.value`

## Page Layouts (4)
- ...

## Validation Rules (1)
- `force-app/main/default/objects/Account/validationRules/Block_Negative_Risk.validationRule-meta.xml`

## Formula Fields (1)
- `Account.Risk_Tier__c` (formula on the same object) — references `Risk_Score__c`

## Flows (2)
- `Account_Risk_Set` — uses Risk_Score__c in a decision element
- ...

## Reports (0)
None in source. (Reports may live only in setup if not source-tracked.)

## Org-only (formula fields on other objects)
- `Opportunity.Account_Risk__c` (formula `Account.Risk_Score__c`)
```

CI JSON / SARIF:
- Each reference becomes one finding with `ruleId: "FIELD-IMPACT"`, `severity: "note"`, file/line populated, message describes the metadata type
- Exit 0 always (this is informational, not a check) unless `--fail-if-found` is passed (then 1 if any references)

### 5. Exit codes
- 0 — informational mode (default), or `--fail-if-found` and no references found
- 1 — `--fail-if-found` and references exist
- 2 — query/setup error

## Rules

- **Be precise about false positives.** When grepping by bare field name, the result may include unrelated symbols. Always prefix the match with `<Object>.` when checking Apex. Note any unresolvable matches in a "Possible matches" section
- **Skip generated files.** `package.xml`, deployment manifests, log files
- **No string `assertEquals` on field name.** Don't bother flagging test class assertions — they're real references but not interesting for impact analysis. Group them in a "Tests (n)" section without per-line detail
- **Time-bound the org-side queries.** If the FieldDefinition query times out (large orgs), report the partial result and continue — don't fail the whole run
