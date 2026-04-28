# Apex Development Standards

Production Apex standards for this Salesforce project. Read alongside `docs/patterns/salesforce-patterns.md` (generic platform patterns) and `docs/patterns/project-patterns.md` (project-specific patterns).

---

## Governor Limits Reference

| Limit | Synchronous | Asynchronous |
|-------|------------|--------------|
| SOQL Queries | 100 | 200 |
| DML Statements | 150 | 150 |
| CPU Time | 10,000 ms | 60,000 ms |
| Heap Size | 6 MB | 12 MB |
| Records Retrieved (total) | 50,000 | 50,000 |
| Callouts | 100 | 100 |
| Future Calls | 50 | 0 |
| Queueable Jobs | 50 | 1 |

---

## Bulkification

Every method that handles records must be bulk-safe (200+ records in trigger context).

```apex
// DO: Collect IDs, query once, process in bulk
Set<Id> accountIds = new Set<Id>();
for (Contact c : Trigger.new) {
    accountIds.add(c.AccountId);
}
Map<Id, Account> accounts = new Map<Id, Account>(
    [SELECT Id, Name FROM Account WHERE Id IN :accountIds]
);

List<Contact> toUpdate = new List<Contact>();
for (Contact c : Trigger.new) {
    Account acc = accounts.get(c.AccountId);
    if (acc != null) {
        c.Account_Name__c = acc.Name;
        toUpdate.add(c);
    }
}
update toUpdate;
```

```apex
// DON'T: SOQL or DML inside loops
for (Contact c : Trigger.new) {
    Account acc = [SELECT Name FROM Account WHERE Id = :c.AccountId]; // BAD
    update c; // BAD
}
```

**Rules**:
- Query outside loops, store in `Map<Id, SObject>`
- Collect records to update in a `List`, DML once after the loop
- Use `Set<Id>` to collect unique IDs before querying
- If cascade updates would exceed limits, offload to Queueable

---

## SOQL

### Query Only What You Need

```apex
// DO: Specific fields
List<Account> accs = [SELECT Id, Name, BillingCity FROM Account WHERE Id IN :ids];

// DON'T: Query unused fields (wastes heap)
List<Account> accs = [SELECT Id, Name, BillingCity, BillingState, BillingCountry,
    BillingPostalCode, Phone, Fax, Website, Industry, AnnualRevenue, NumberOfEmployees,
    Description, OwnerId, CreatedDate, LastModifiedDate FROM Account WHERE Id IN :ids];
```

### Use Relationship Queries

```apex
// DO: One query with child relationship
List<Account> accs = [
    SELECT Id, Name,
           (SELECT Id, LastName, Email FROM Contacts WHERE Contact_Status__c = 'Active')
    FROM Account WHERE Id IN :accountIds
];

// DON'T: Two separate queries
List<Account> accs = [SELECT Id, Name FROM Account WHERE Id IN :accountIds];
List<Contact> contacts = [SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds];
```

### SOQL Injection Prevention

```apex
// DO: Bind variables (always preferred)
String name = userInput;
List<Account> accs = [SELECT Id FROM Account WHERE Name = :name];

// DO: escapeSingleQuotes for dynamic ORDER BY or field names
String sortField = String.escapeSingleQuotes(userInput);
String query = 'SELECT Id, Name FROM Account ORDER BY ' + sortField + ' ASC';

// DO: Whitelist approach for dynamic fields
private static final Set<String> ALLOWED_SORT_FIELDS = new Set<String>{
    'Name', 'CreatedDate', 'BillingCity'
};
if (!ALLOWED_SORT_FIELDS.contains(sortField)) {
    throw new IllegalArgumentException('Invalid sort field');
}

// DON'T: Concatenate user input into WHERE clauses
String query = 'SELECT Id FROM Account WHERE Name = \'' + userInput + '\''; // VULNERABLE
```

### CRUD/FLS Enforcement

```apex
// DO: WITH USER_MODE (recommended — enforces CRUD, FLS, and sharing)
List<Account> accs = [SELECT Id, Name FROM Account WITH USER_MODE WHERE Id IN :ids];

// DO: AccessLevel.USER_MODE for dynamic SOQL
List<Account> accs = Database.query(query, AccessLevel.USER_MODE);

// DO: stripInaccessible for graceful degradation (returns records minus inaccessible fields)
SObjectAccessDecision decision = Security.stripInaccessible(AccessLevel.READABLE, accounts);
List<Account> safeAccounts = (List<Account>) decision.getRecords();

// DON'T: No security enforcement
List<Account> accs = [SELECT Id, Confidential_Field__c FROM Account]; // Bypasses FLS
```

---

## DML

### Database Methods vs DML Statements

```apex
// DO: Database.insert for partial success handling
List<Database.SaveResult> results = Database.insert(records, false); // allOrNone=false
for (Integer i = 0; i < results.size(); i++) {
    if (!results[i].isSuccess()) {
        for (Database.Error err : results[i].getErrors()) {
            Logger.log('Insert failed: ' + err.getMessage(), records[i].Id);
        }
    }
}

// DO: AccessLevel.USER_MODE for sharing enforcement
Database.insert(record, AccessLevel.USER_MODE);
Database.update(records, AccessLevel.USER_MODE);

// DO: Simple insert when all-or-nothing is acceptable
try {
    insert records;
} catch (DmlException e) {
    throw new AuraHandledException('Insert failed: ' + e.getMessage());
}
```

### Mixed DML

Setup objects (User, Group, PermissionSet) and non-setup objects (Account, Contact) cannot have DML in the same transaction.

```apex
// DO: Use @future or Queueable for mixed DML
public static void createUserAndAccount(String name, String email) {
    Account acc = new Account(Name = name);
    insert acc; // Non-setup DML

    // Use future for setup object DML
    createUserAsync(email, acc.Id);
}

@future
private static void createUserAsync(String email, Id accountId) {
    // Setup DML in separate transaction
}
```

---

## Error Handling

### AuraHandledException for LWC Methods

```apex
// DO: Validate → business logic → DML, with layered catch blocks
@AuraEnabled
public static Contact createContact(String firstName, String lastName, Id accountId) {
    try {
        // 1. Input validation
        if (String.isBlank(lastName)) {
            throw new IllegalArgumentException('Last name is required');
        }
        if (accountId == null) {
            throw new IllegalArgumentException('Account is required');
        }

        // 2. Business logic
        Contact c = new Contact(
            FirstName = firstName,
            LastName = lastName,
            AccountId = accountId
        );

        // 3. DML with sharing enforcement
        Database.insert(c, AccessLevel.USER_MODE);
        return c;

    } catch (IllegalArgumentException ex) {
        throw new AuraHandledException(ex.getMessage());
    } catch (DmlException ex) {
        throw new AuraHandledException('Failed to create contact: ' + ex.getDmlMessage(0));
    } catch (Exception ex) {
        Logger.log('Unexpected error in createContact', ex);
        throw new AuraHandledException('An unexpected error occurred');
    }
}
```

**Rules**:
- Catch specific exceptions first (`IllegalArgumentException`, `DmlException`), generic `Exception` last
- Never expose stack traces to users — log internally, return clean messages
- `AuraHandledException` is the ONLY exception type LWC can read the message from
- For cacheable methods, throw `AuraHandledException` directly (no try-catch needed for simple queries)

### Logging

If the project provides a `Logger` utility (check `docs/patterns/project-patterns.md` and `docs/project-context.md`), use it whenever an unexpected error is caught:

```apex
catch (Exception ex) {
    Logger.log('Context message', ex); // Logs to the project's persistent log table
    throw new AuraHandledException('User-friendly message');
}
```

If the project has no Logger utility, fall back to `System.debug()` for diagnostics — never silently swallow an exception.

---

## Security

### Sharing Model

```apex
// DO: with sharing (default — respects record-level security)
public with sharing class PortalController {
    // Users only see records they have access to
}

// USE SPARINGLY: without sharing (justify with comment)
// Required when: admin operations, aggregation across all records, background jobs
public without sharing class AdminReportService {
    // REASON: Aggregates data across all orgs for admin dashboard
}

// DO: inherited sharing for utility classes
public inherited sharing class Utilities {
    // Inherits sharing context from caller
}
```

**Project convention**: `with sharing` by default (see `platform.sharingDefault` in `.claude/sf-project.json`). Document the reason in code comments if using `without sharing`.

### Input Validation Order

Always validate in this order:
1. Null/blank checks on all parameters
2. Type/format validation (valid Id, valid email, etc.)
3. Business rule validation (user has access, record exists, etc.)
4. Then proceed to DML

---

## Async Apex

### When to Use What

| Need | Use | Why |
|------|-----|-----|
| Simple fire-and-forget, only primitives | `@future` | Lowest overhead |
| Complex logic, needs sObject params | `Queueable` | Accepts any data type |
| Process 1000+ records | `Batch` | Gets own governor limits per chunk |
| Run on a schedule | `Schedulable` | Cron-based execution |
| Cascading work from trigger | `Queueable` with static guard | Prevents multiple enqueues |

### Queueable with Guard

Prevent multiple enqueues per transaction with a static boolean flag (see PRJ-6 in `docs/patterns/project-patterns.md` for the project's reference handler):

```apex
private static Boolean queueEnqueued = false;

public void AfterUpdate(Map<Id, SObject> newItems, Map<Id, SObject> oldItems) {
    // ... collect work ...

    if (!queueEnqueued && !workMap.isEmpty()) {
        MyQueueable job = new MyQueueable();
        job.workMap = workMap;
        queueEnqueued = true;
        System.enqueueJob(job);
    }
}
```

### Batch Best Practices

```apex
public class MyBatch implements Database.Batchable<sObject>, Database.Stateful {
    private Integer successCount = 0;
    private Integer failCount = 0;

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator('SELECT Id, Name FROM Account WHERE NeedsProcessing__c = true');
    }

    public void execute(Database.BatchableContext ctx, List<Account> scope) {
        // scope default = 200, good for most cases
        List<Account> toUpdate = new List<Account>();
        for (Account acc : scope) {
            acc.ProcessedDate__c = System.today();
            toUpdate.add(acc);
        }
        List<Database.SaveResult> results = Database.update(toUpdate, false);
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) { successCount++; } else { failCount++; }
        }
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug('Done. Success: ' + successCount + ', Failed: ' + failCount);
    }
}

// Invoke with scope size
Database.executeBatch(new MyBatch(), 200);
```

---

## Test Classes

### Structure

```apex
@IsTest
private class MyControllerTest {

    @TestSetup
    static void setup() {
        // Shared test data — runs once, available to all test methods
        Account acc = new Account(Name = 'Test Org');
        insert acc;
        Contact c = new Contact(LastName = 'Test', AccountId = acc.Id);
        insert c;
    }

    @IsTest
    static void testGetRecords_positive() {
        Test.startTest();
        List<Contact> result = MyController.getContacts(
            [SELECT Id FROM Account LIMIT 1].Id
        );
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return 1 contact');
        System.assertEquals('Test', result[0].LastName, 'Last name should match');
    }

    @IsTest
    static void testGetRecords_noResults() {
        Test.startTest();
        List<Contact> result = MyController.getContacts('001000000000000AAA');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty list for invalid account');
    }

    @IsTest
    static void testCreateRecord_validation() {
        Test.startTest();
        try {
            MyController.createContact(null, null, null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), 'Should contain validation message');
        }
        Test.stopTest();
    }

    @IsTest
    static void testBulk_200Records() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 200; i++) {
            contacts.add(new Contact(LastName = 'Bulk ' + i, AccountId = acc.Id));
        }
        insert contacts;

        Test.startTest();
        List<Contact> result = MyController.getContacts(acc.Id);
        Test.stopTest();

        System.assert(result.size() >= 200, 'Should handle 200+ records');
    }
}
```

**Rules**:
- `@TestSetup` for shared data — don't repeat data creation in every method
- `Test.startTest()` / `Test.stopTest()` resets governor limits and executes async
- Name tests: `test{Method}_{scenario}` (e.g., `testGetContacts_positive`, `testGetContacts_noResults`)
- Always include assertion messages: `System.assertEquals(expected, actual, 'descriptive message')`
- Test bulk (200+ records), positive case, negative/validation case, and edge cases
- Never use `@IsTest(SeeAllData=true)` unless testing against org config (custom metadata, etc.)
- Never hardcode record IDs
- For custom metadata mocking, use `@TestVisible` private variables to inject mock records — search the project's existing controllers for an example
- Target the coverage threshold from `quality.codeCoverageTarget` in `.claude/sf-project.json` (typical default: 85%) — coverage without meaningful assertions is meaningless

---

## Naming Conventions

| Construct | Pattern | Example |
|-----------|---------|---------|
| Controller (LWC-facing) | `{Feature}Controller` | `PortalPostsListController` |
| Service (business logic) | `{Feature}Service` | `CrispPostService` |
| Trigger handler | `{Object}TriggerHandler` | `ContactTriggerHandler` |
| Batch | `{Feature}Batchable` | `NotificationCleanupBatchable` |
| Schedulable | `{Feature}Schedulable` | `NotificationCleanupSchedulable` |
| Queueable | `{Feature}Queueable` | `ContactTriggerHandlerQueueable` |
| Test class | `{ClassName}Test` | `PortalPostsListControllerTest` |
| Utility | `{Domain}Utilities` / `{Domain}Utils` | `CRISPUtilities`, `DefangUtils` |
| Interface | `I{Name}` | `ITriggerHandler` |
| Constants | `UPPER_SNAKE_CASE` | `BATCH_SIZE`, `RATING_VALUE_YES` |
| Methods | `camelCase`, action verbs | `getTablePosts()`, `createRating()` |
| Variables | `camelCase`, descriptive | `accountIds`, `totalRecords`, `isProcessing` |

---

## Code Organization

### Separation of Concerns

```
Trigger (1 line)  →  TriggerHandler (routing)  →  Service (business logic)
                                                    ↓
LWC  →  Controller (@AuraEnabled)  →  Service (shared logic)  →  Selector (queries)
```

- **Trigger**: One-liner delegating to `TriggerDispatcher.Run(new Handler())`
- **TriggerHandler**: Implements `ITriggerHandler`, routes to service methods
- **Controller**: `@AuraEnabled` methods that validate input and delegate to services
- **Service**: Reusable business logic (can be called from triggers AND controllers)
- **Selector**: SOQL queries (optional — extract when queries are reused across classes)
- **Utility**: Stateless helper methods (string manipulation, date formatting, etc.)

### Method Guidelines

- Keep methods under 50 lines — extract helpers for clarity
- One method = one responsibility
- Public methods document the contract; private methods do the work
- Static methods for stateless operations (most Apex controller/service work)
- Instance methods only when state is needed (Batch `Database.Stateful`, Queueable)
