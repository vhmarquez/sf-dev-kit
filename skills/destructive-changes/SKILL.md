---
name: destructive-changes
description: Build a Salesforce `destructiveChanges.xml` interactively from a list of components to delete. Validates that nothing else in source still references them before authoring the file.
data-access: metadata-only
---

You are building a `destructiveChanges.xml` file (and the matching `package.xml` placeholder) to delete metadata from a Salesforce org. Destructive changes are the only safe way to delete components on deploy — manual UI deletes don't propagate.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
LWC_SRC="$(sf_config_get '.paths.lwcSource' "$ENV")"
API_VERSION="$(sf_config_get '.platform.apiVersion' "$ENV")"
```

## Input

`$ARGUMENTS`:
- `add <metadataType>:<fullName>` — add a component to the destructive set (e.g., `ApexClass:OrderHelper`, `CustomField:Account.Old_Field__c`)
- `add-from <file>` — read components from a file (one per line, same format)
- `preview` — print the current destructive set
- `validate` — verify no source still references the listed components
- `write [<dir>]` — author `destructiveChanges.xml` + `package.xml` to `<dir>` (default `manifest/destructive/`)
- `clear` — wipe the in-progress set
- `--ci` — machine output

## State

The in-progress set lives in `${CLAUDE_PLUGIN_DATA}/sf-dev-kit/destructive/<project>/pending.json`:
```json
{
  "items": [
    {"type": "ApexClass", "fullName": "OrderHelper"},
    {"type": "CustomField", "fullName": "Account.Old_Field__c"}
  ],
  "lastModified": "2026-04-28T14:45:00Z"
}
```

## Steps

### `add <Type>:<fullName>`

Validate type against the supported list (ApexClass, ApexTrigger, LightningComponentBundle, CustomObject, CustomField, ValidationRule, Layout, FlowDefinition, PermissionSet, etc.).

For `CustomField`, fullName format is `<Object>.<Field>` (e.g., `Account.Old_Field__c`).

Append to the pending set; refuse duplicates.

### `validate`

For each pending item, run the equivalent of `/sf-dev-kit:field-impact` (for fields) or a grep for the symbol (for classes/components):
- ApexClass: grep references to `ClassName.` and `new ClassName(`
- LightningComponentBundle: grep `c-<lwc-name>` in HTML and `from 'c/<lwcName>'` in JS
- CustomField: full field-impact across all metadata types
- CustomObject: every reference to `<Object>__c` in queries, layouts, profiles, perms, flows
- FlowDefinition: every Apex `Flow.Interview` lookup of the developer name

Report:
- ✅ if no references found in source
- ⚠️ if references exist (list them; refuse to write until cleaned up or user passes `--force`)

### `write [<dir>]`

Generate two files:

`<dir>/destructiveChanges.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>OrderHelper</members>
        <name>ApexClass</name>
    </types>
    <types>
        <members>Account.Old_Field__c</members>
        <name>CustomField</name>
    </types>
    <version>{{platform.apiVersion}}</version>
</Package>
```

`<dir>/package.xml` (empty placeholder required by the API):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <version>{{platform.apiVersion}}</version>
</Package>
```

Print the deploy command:
```
sf project deploy start --target-org <ORG> --manifest <dir>/package.xml --post-destructive-changes <dir>/destructiveChanges.xml --wait 30
```

(Use `--pre-destructive-changes` if the deletion must happen before the deploy of new components.)

## Output

Default Markdown after `validate`:
```
# Destructive Changes Validation

Pending items: 3

| Type | Full Name | Source refs | Verdict |
|------|-----------|-------------|---------|
| ApexClass | OrderHelper | 0 | ✅ safe to delete |
| CustomField | Account.Old_Field__c | 2 (in OrderController.cls:42, acmeAccountForm.html:18) | ⚠️ in use |
| FlowDefinition | Old_Auto_Assign | 0 | ✅ safe to delete |

⚠️ Cannot write destructive set — clean up references first or pass `--force`.
```

Default after `write`:
```
# Destructive Changes Written

Files written:
- manifest/destructive/destructiveChanges.xml (3 items)
- manifest/destructive/package.xml (placeholder)

## Deploy command
sf project deploy start \
  --target-org DevVM \
  --manifest manifest/destructive/package.xml \
  --post-destructive-changes manifest/destructive/destructiveChanges.xml \
  --wait 30

## Pre vs Post Destructive
- Use `--post-destructive-changes` (default) when the deletion can happen after new components deploy
- Use `--pre-destructive-changes` when the new components depend on the deletion (e.g., renaming a field requires deleting the old name first)

## Reminder
Run `/sf-dev-kit:diff-deploy --validate` first against prod to catch Salesforce-side dependency errors that source-side validation can't see.
```

## Exit codes
- 0 — operation succeeded
- 1 — validate found references (default refuse to write)
- 2 — invocation error / type unsupported

## Rules

- **Always validate before writing.** Source-side reference checks catch most accidental deletions
- **Don't write directly into deploy.** This skill produces the manifest; the user (or CI) runs the deploy
- **Pre vs post matters.** Document both; default to post (the safe default)
- **Refuse if references exist** unless the user passes `--force` and accepts responsibility — don't make destruction easy
- **Persist state across sessions.** The pending file lets the user `add` over multiple sessions before writing

## Consumers

- Release pipeline: build the destructive manifest as part of a release that retires legacy components
- `/sf-dev-kit:field-impact` is the underlying scanner for `validate` mode
