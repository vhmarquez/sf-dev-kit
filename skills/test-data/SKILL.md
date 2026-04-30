---
name: test-data
description: Scaffold an Apex `TestDataFactory` for an sObject using its required fields and project-context defaults. Outputs a class with `make<Object>()`, `make<Object>(overrides)`, and `make<Object>List(count, overrides)` methods, plus a sensible defaults map. Saves the most tedious part of writing tests.
data-access: none
---

You are scaffolding an Apex `TestDataFactory` for one or more sObjects. The factory provides a stable way to build valid test records (all required fields populated) with optional per-test overrides.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
TEST_SUFFIX="$(sf_config_get '.naming.apex.testSuffix' "$ENV")"   # default: Test
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
```

## Input

`$ARGUMENTS`: required.
- `<Object>` — generate a factory method for one sObject (e.g., `Account`)
- `<Object1> <Object2> ...` — multiple objects in one factory class
- `--class-name <Name>` — override factory class name (default `TestDataFactory`)
- `--out <path>` — write to a specific path (default `${APEX_SRC}/TestDataFactory.cls`)
- `--update` — append methods to an existing factory rather than replacing

## Steps

### 1. Resolve required fields per sObject

Prefer the org cache (`${CLAUDE_PLUGIN_DATA}/argo/org-cache/<org>.json`) — it has the full describe. If absent, fall back to live `sf_cli_describe <Object> <ORG>`.

For each field, capture:
- `name` (API name)
- `type` (string, picklist, reference, currency, date, etc.)
- `nillable` — required if `false`
- `defaultValueFormula` — if set, no need to populate
- `referenceTo` — for lookups, the target sObject
- `picklistValues` — first active value as default
- `length` — for strings, set test value to a stable short value

### 2. Generate the factory class

```apex
@isTest
public class TestDataFactory {

    // ---------- Account ------------------------------------------------------
    public static Account makeAccount() {
        return makeAccount(new Map<String,Object>());
    }

    public static Account makeAccount(Map<String, Object> overrides) {
        Account a = new Account(
            Name = 'Test Account ' + uniq()
            // (other required fields populated here)
        );
        applyOverrides(a, overrides);
        insert a;
        return a;
    }

    public static List<Account> makeAccountList(Integer count, Map<String, Object> overrides) {
        List<Account> rows = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            Account a = new Account(
                Name = 'Test Account ' + uniq() + '-' + i
            );
            rows.add(a);
        }
        for (Account a : rows) applyOverrides(a, overrides);
        insert rows;
        return rows;
    }

    // ---------- Contact (lookup → Account) ----------------------------------
    public static Contact makeContact(Id accountId) {
        return makeContact(accountId, new Map<String, Object>());
    }

    public static Contact makeContact(Id accountId, Map<String, Object> overrides) {
        if (accountId == null) accountId = makeAccount().Id;
        Contact c = new Contact(
            LastName = 'Test ' + uniq(),
            AccountId = accountId
        );
        applyOverrides(c, overrides);
        insert c;
        return c;
    }

    // ---------- shared -------------------------------------------------------

    public static Map<String, Object> overrides(String key, Object value) {
        return new Map<String, Object>{ key => value };
    }

    private static Integer counter = 0;
    private static String uniq() {
        counter++;
        return String.valueOf(System.currentTimeMillis()) + '-' + counter;
    }

    private static void applyOverrides(SObject record, Map<String, Object> overrides) {
        if (overrides == null) return;
        for (String field : overrides.keySet()) {
            record.put(field, overrides.get(field));
        }
    }
}
```

### 3. Generate the meta file

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>{{platform.apiVersion}}</apiVersion>
    <status>Active</status>
</ApexClass>
```

### 4. Per-type defaults

| sObject field type | Default test value |
|--------------------|--------------------|
| string / textarea  | `'Test ' + uniq()` |
| email              | `uniq() + '@example.com'` |
| phone              | `'555-555-' + uniq().right(4)` |
| currency / number  | `100` |
| percent            | `50` |
| date               | `Date.today()` |
| datetime           | `Datetime.now()` |
| boolean            | `false` |
| picklist (required) | first active value from describe |
| picklist (optional) | omitted |
| reference (required) | call the appropriate `make<Parent>()` factory and use `.Id` |
| reference (optional) | omitted |
| reference (User)   | `UserInfo.getUserId()` |
| record-type ID     | first active record type from describe |

### 5. Multi-object factories preserve order

When multiple objects are given, generate factories in **dependency order** (parent before child). E.g., `Order_Item__c, Order__c, Account` → emit `makeAccount`, `makeOrder`, `makeOrderItem` (Account → Order → OrderItem).

### 6. Output

Write `${APEX_SRC}/<ClassName>.cls` and `<ClassName>.cls-meta.xml`. Print a summary:

```
[test-data] Wrote TestDataFactory.cls (3 sObjects: Account, Order__c, Order_Item__c)
[test-data] Required fields populated; lookups resolved through factories
[test-data] Update with: /argo:test-data --update Contact
```

If `--update` was passed and the factory already exists, append new methods (do not duplicate; idempotent insert).

### 7. Exit codes
- 0 — factory written
- 1 — sObject(s) not found in cache and `sf` CLI not available
- 2 — write error / config error

## Rules

- **Insert by default.** `make<Object>()` returns an inserted record so tests can use `.Id` directly. Override pattern: `make<Object>(overrides)` for fields, `makeMemoryOnly<Object>()` if you need a non-inserted record (rare; only generate that variant if the user asks)
- **Always use `with sharing` semantics implicitly** — factory is `@isTest` annotated so it runs with test context
- **Don't use `Test.loadData`.** It depends on static resources and breaks when fields change
- **Don't hardcode IDs.** Always derive lookup values from another factory call
- **Don't pre-populate audit fields** (`CreatedDate`, `LastModifiedDate`); they'd be ignored anyway, and tests that need to fake them should use `Test.setCreatedDate`
- **Counter + timestamp uniqueness** for any field that needs to be unique across rows (Email, ExternalId, Username)
