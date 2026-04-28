# Salesforce Code Patterns

Reusable Salesforce-platform patterns. These apply to any Salesforce project — they describe techniques, not project-specific components or channels. For project-specific patterns (LMS channels, shared components, logging utility, etc.), see `docs/patterns/project-patterns.md`.

> **Conventions used below**: code samples use placeholder names (`MyComponent`, `MyController`, `Account`, `Contact`, `Status__c`) — replace with real names from your project. The LWC component names in JavaScript imports use a generic `c/myComponent` form; substitute your project's prefix from `.claude/sf-project.json` (`naming.lwc.prefix`).

---

## SF-1: Paginated Datatable (LWC) {#paginated-datatable}

Offset-based pagination with sorting, filtering, and page controls.

```javascript
export default class MyListComponent extends LightningElement {
    @track totalPages = 0;
    @track totalRecords = 0;
    @track pageSize = 10;
    @track page = 1;
    @track nextButtonDisabled = false;
    @track prevButtonDisabled = true;
    @track sortedBy = 'CreatedDate';
    @track sortedDirection = 'desc';
    @track spinner = true;

    // Separate wire for count (drives pagination UI)
    @wire(getTableRecordsCount, { filters: '$filters' })
    wiredCount(result) {
        this.countResult = result;
        if (result.data !== undefined) {
            this.totalRecords = result.data;
            this.totalPages = Math.ceil(result.data / this.pageSize);
            this.updatePaginationButtons();
        }
    }

    // Separate wire for data (drives table)
    @wire(getTableRecords, {
        pageSize: '$pageSize', page: '$page',
        sortedBy: '$sortedBy', sortedDirection: '$sortedDirection',
        filters: '$filters'
    })
    wiredData(result) {
        this.dataResult = result;
        if (result.data) {
            this.records = result.data;
            this.spinner = false;
        }
    }

    get recordRange() {
        if (this.totalRecords === 0) return '0-0 of 0';
        const start = (this.page - 1) * this.pageSize + 1;
        const end = Math.min(this.page * this.pageSize, this.totalRecords);
        return `${start}-${end} of ${this.totalRecords}`;
    }

    nextPage() {
        if (this.page < this.totalPages) { this.page += 1; this.updatePaginationButtons(); }
    }

    previousPage() {
        if (this.page > 1) { this.page -= 1; this.updatePaginationButtons(); }
    }

    updatePaginationButtons() {
        this.prevButtonDisabled = this.page === 1;
        this.nextButtonDisabled = this.page >= this.totalPages;
    }

    sortColumn(event) {
        const field = event.detail.fieldName;
        this.sortedDirection = this.sortedBy === field
            ? (this.sortedDirection === 'asc' ? 'desc' : 'asc')
            : 'desc';
        this.sortedBy = field;
        this.page = 1;
    }

    setPageSize(event) {
        this.pageSize = parseInt(event.detail.value, 10);
        this.page = 1;
        this.totalPages = Math.ceil(this.totalRecords / this.pageSize);
        this.updatePaginationButtons();
    }
}
```

**Rules**:
- Two separate `@wire` calls: one for count, one for data
- Reset `page = 1` when filters, sort, or page size change
- When `pageSize` is a reactive `@wire` parameter (`$pageSize`), changing it automatically re-fires the wire — do not make an extra imperative call in `setPageSize()`
- Use `refreshApex()` for manual refresh after imperative operations
- Store wire results for `refreshApex()`: `this.dataResult = result`
- **Exception**: For hierarchical data (e.g., accordion of Account → Contact → Device), a single imperative Apex call returning nested wrappers is acceptable — the two-wire pattern does not apply

---

## SF-2: Record Detail View (LWC) {#record-detail}

Multi-wire pattern for displaying record data with field metadata.

```javascript
import { LightningElement, api, wire, track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import FIELD_NAME from '@salesforce/schema/Account.Name';
import FIELD_ACRONYM from '@salesforce/schema/Account.Acronym__c';

const FIELDS = [FIELD_NAME, FIELD_ACRONYM];

export default class MyDetailComponent extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this.recordName = data.fields.Name.value;
        }
    }

    @wire(getObjectInfo, { objectApiName: 'Account' })
    wiredObjectInfo({ data, error }) {
        if (data) {
            this.fieldHelpText = data.fields.Acronym__c.inlineHelpText;
        }
    }
}
```

**Rules**:
- Import fields via `@salesforce/schema/Object.Field` for compile-time safety
- Use `getObjectInfo` for field help text and metadata
- Chain dependent wires using reactive `$property` parameters

---

## SF-3: LMS Subscription Lifecycle (LWC) {#lms-subscription}

Subscribe to a Lightning Message Service channel. The channel itself is project-specific — see `docs/project-context.md` for the channels available in this project and `docs/patterns/project-patterns.md` for the project's wrapper pattern. The lifecycle below is the platform-generic technique.

```javascript
import { LightningElement, wire, track } from 'lwc';
import { publish, subscribe, unsubscribe, MessageContext } from "lightning/messageService";
import myChannel from '@salesforce/messageChannel/My_Channel__c';

export default class MyComponent extends LightningElement {
    subscription = null;

    @wire(MessageContext) messageContext;

    connectedCallback() {
        this.subscribeToMessageChannel();
    }

    renderedCallback() {
        if (!this.subscription) {
            this.subscribeToMessageChannel();
        }
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = null;
        }
    }

    subscribeToMessageChannel() {
        if (this.messageContext && !this.subscription) {
            this.subscription = subscribe(
                this.messageContext,
                myChannel,
                (message) => this.handleMessage(message)
            );
            this.requestData();
        }
    }

    requestData() {
        if (this.messageContext) {
            publish(this.messageContext, myChannel, { type: 'request' });
        }
    }

    handleMessage(message) {
        if (message.type === 'data') {
            // Assign needed properties from message
        }
    }
}
```

**Rules**:
- Subscribe in `connectedCallback()`, guard in `renderedCallback()`, unsubscribe in `disconnectedCallback()`
- The `renderedCallback()` guard is **mandatory** — without it, re-renders create duplicate subscriptions
- Always publish `{ type: 'request' }` after subscribing if your channel uses a request/response convention
- Only process messages with the expected `type` to avoid acting on your own request frames
- Store subscription in an instance variable to detect duplicates

---

## SF-4: XML Meta Config (LWC) {#xml-meta}

Standard component exposure for Experience Cloud. Adjust `<targets>` to match `platform.lwcTargets` from `.claude/sf-project.json` if your project targets Lightning Experience or Mobile instead.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>66.0</apiVersion>
    <isExposed>true</isExposed>
    <masterLabel>My Component</masterLabel>
    <description>One-sentence purpose matching the doc-file Purpose line.</description>
    <targets>
        <target>lightningCommunity__Page</target>
        <target>lightningCommunity__Default</target>
    </targets>
</LightningComponentBundle>
```

**Rules**:
- API version must match `platform.apiVersion` from `.claude/sf-project.json`
- `isExposed=true` for Experience Cloud
- Targets must match `platform.lwcTargets` from `.claude/sf-project.json`
- Use a readable `masterLabel` and a one-sentence `description`
- For Experience Builder-configurable `@api` properties, declare them in `<targetConfigs>`:

```xml
<targetConfigs>
    <targetConfig targets="lightningCommunity__Default">
        <property name="cardTitle" type="String" label="Card Title" default="My Component" />
    </targetConfig>
</targetConfigs>
```

---

## SF-5: Paginated Apex Controller {#paginated-controller}

Paired data + count methods for LWC pagination.

```apex
public with sharing class MyController {

    @AuraEnabled(cacheable=true)
    public static List<SObject> getTableRecords(
            String parentId, Integer pageSize, Integer page,
            String sortedBy, String sortedDirection, List<String> filterBy) {

        Integer offset = pageSize * (page - 1);
        String query = 'SELECT Id, Name, Email FROM Contact WHERE AccountId = :parentId';

        if (!filterBy.isEmpty()) {
            query += ' AND Status__c IN :filterBy';
        }

        if (sortedBy != null && ALLOWED_SORT_FIELDS.contains(sortedBy)) {
            query += ' ORDER BY ' + sortedBy
                   + ' ' + (sortedDirection == 'asc' ? 'ASC' : 'DESC') + ' NULLS LAST';
        }

        query += ' LIMIT :pageSize OFFSET :offset';
        return Database.query(query);
    }

    @AuraEnabled(cacheable=true)
    public static Integer getTableRecordsCount(String parentId, List<String> filterBy) {
        String query = 'SELECT COUNT() FROM Contact WHERE AccountId = :parentId';

        if (!filterBy.isEmpty()) {
            query += ' AND Status__c IN :filterBy';
        }

        return Database.countQuery(query);
    }
}
```

**Rules**:
- Both methods `@AuraEnabled(cacheable=true)`
- Offset: `pageSize * (page - 1)`
- Use bind variables (`:paramName`) for filter values — never concatenate user input
- Separate count method mirrors the data method's WHERE clause exactly
- For dynamic field names, validate against a whitelist (see SF-9: Filter Whitelist Validation) — `String.escapeSingleQuotes()` alone is insufficient, it prevents value injection but not field-name injection

---

## SF-6: AuraEnabled Methods (Cacheable vs Writes) {#aura-enabled}

Cacheable reads vs non-cacheable writes with error handling.

**Cacheable (read-only)**:
```apex
@AuraEnabled(cacheable=true)
public static MyMetadata__mdt getActiveRecord() {
    List<MyMetadata__mdt> records = [
        SELECT Id, Title__c FROM MyMetadata__mdt
        WHERE Active__c = true ORDER BY CreatedDate DESC LIMIT 1
    ];
    if (records.isEmpty()) {
        throw new AuraHandledException('No active record found.');
    }
    return records[0];
}
```

**Non-cacheable (DML)**:
```apex
@AuraEnabled
public static MyRecord__c createRecord(Id parentId, String value) {
    try {
        // 1. Input validation
        if (parentId == null) {
            throw new IllegalArgumentException('Parent ID cannot be null');
        }
        // 2. Business logic
        if (recordAlreadyExists(parentId)) {
            throw new IllegalArgumentException('Record already exists for this parent.');
        }
        // 3. DML with user-mode sharing
        MyRecord__c rec = new MyRecord__c(Parent__c = parentId, Value__c = value);
        Database.insert(rec, AccessLevel.USER_MODE);
        return rec;
    } catch (IllegalArgumentException ex) {
        throw new AuraHandledException(ex.getMessage());
    } catch (Exception ex) {
        throw new AuraHandledException('Unable to create record: ' + ex.getMessage());
    }
}
```

**Rules**:
- `cacheable=true` for queries only — no DML allowed
- Always throw `AuraHandledException` for user-facing errors
- Use `AccessLevel.USER_MODE` on DML to enforce sharing
- Validate inputs → business rules → DML → return
- Catch `IllegalArgumentException` separately for clean messages
- Cacheable methods using `Database.query()` (dynamic SOQL) should also wrap in try-catch — query construction errors throw uncaught `QueryException`

---

## SF-7: Trigger Handler Framework {#trigger-handler}

All triggers delegate to handler classes via a `TriggerDispatcher` framework. Most projects bring their own dispatcher; if yours doesn't have one, search the codebase for an existing implementation before creating one.

**Trigger file** (one-liner):
```apex
trigger ContactTrigger on Contact (before insert, before update, before delete,
        after insert, after update, after delete, after undelete) {
    TriggerDispatcher.Run(new ContactTriggerHandler());
}
```

**Handler class** (implements `ITriggerHandler`):
```apex
public with sharing class ContactTriggerHandler implements ITriggerHandler {

    public Boolean IsDisabled() { return false; }

    public void BeforeInsert(List<SObject> newItems) { /* logic */ }
    public void BeforeUpdate(Map<Id, SObject> newItems, Map<Id, SObject> oldItems) { /* logic */ }
    public void BeforeDelete(Map<Id, SObject> oldItems) {}
    public void AfterInsert(Map<Id, SObject> newItems) { /* logic */ }
    public void AfterUpdate(Map<Id, SObject> newItems, Map<Id, SObject> oldItems) {
        for (Id recordId : newItems.keySet()) {
            SObject newRecord = newItems.get(recordId);
            SObject oldRecord = oldItems.get(recordId);
            // Compare field changes...
        }
    }
    public void AfterDelete(Map<Id, SObject> oldItems) {}
    public void AfterUndelete(Map<Id, SObject> oldItems) {}
}
```

**Interface** (`ITriggerHandler`):
```apex
public interface ITriggerHandler {
    void BeforeInsert(List<SObject> newItems);
    void BeforeUpdate(Map<Id, SObject> newItems, Map<Id, SObject> oldItems);
    void BeforeDelete(Map<Id, SObject> oldItems);
    void AfterInsert(Map<Id, SObject> newItems);
    void AfterUpdate(Map<Id, SObject> newItems, Map<Id, SObject> oldItems);
    void AfterDelete(Map<Id, SObject> oldItems);
    void AfterUndelete(Map<Id, SObject> oldItems);
    Boolean IsDisabled();
}
```

**Rules**:
- Trigger file is always a one-liner: `TriggerDispatcher.Run(new HandlerClass())`
- Handler implements all `ITriggerHandler` methods (empty body for unused events)
- `BeforeInsert` receives `List<SObject>`; all others receive `Map<Id, SObject>`
- Use static boolean guards for async work — prevent multiple Queueable enqueues per transaction
- `IsDisabled()` can check custom metadata/settings for runtime disable

---

## SF-8: Toast Notifications (LWC) {#toast}

Standard pattern for success/error/warning feedback.

```javascript
import Toast from 'lightning/toast';

// Success
Toast.show({
    label: 'Record updated successfully.',
    mode: 'dismissible',
    variant: 'success'
}, this);

// Error (from Apex catch)
Toast.show({
    label: error?.body?.message || 'An unexpected error occurred.',
    mode: 'sticky',
    variant: 'error'
}, this);

// Warning
Toast.show({
    label: 'File preview is not available for this type.',
    mode: 'dismissible',
    variant: 'warning'
}, this);
```

**Rules**:
- Use `lightning/toast` with `Toast.show()` — current API. Avoid the older `lightning/platformShowToastEvent` with `ShowToastEvent` in new code
- Always pass `this` as the second argument (component context)
- Use `mode: 'dismissible'` for success/warning, `mode: 'sticky'` for errors so the user can read the message
- Extract Apex error messages from `error?.body?.message` with a fallback string
- Keep labels concise — one sentence, action-oriented ("Record updated" not "The record has been successfully updated in the system")

---

## SF-9: Wrapper / DTO Classes (Apex) {#wrapper-dto}

Inner classes that structure complex data returned from Apex to LWC.

```apex
public with sharing class MyController {

    public class PageResult {
        @AuraEnabled public List<ItemWrapper> items;
        @AuraEnabled public Integer totalCount;
    }

    public class ItemWrapper {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String Status;
        @AuraEnabled public List<ChildWrapper> children;
    }

    public class ChildWrapper {
        @AuraEnabled public String Id;
        @AuraEnabled public String Label;
    }

    @AuraEnabled(cacheable=true)
    public static PageResult getData(Integer pageSize, Integer pageNumber) {
        PageResult result = new PageResult();
        result.items = new List<ItemWrapper>();
        // ... query and populate ...
        return result;
    }
}
```

**Rules**:
- Every field exposed to LWC must have `@AuraEnabled` — fields without it are silently dropped during serialization
- Use descriptive wrapper names: `{Entity}Wrapper` or `{Purpose}DTO`
- Keep wrapper fields as simple types (`String`, `Integer`, `Boolean`, `List`) — avoid `SObject` fields when the LWC needs only a subset
- Nest wrappers for hierarchical data rather than returning flat lists the LWC must reassemble
- UI state fields (e.g., `isExpanded`, `cssClass`) may be included but are usually better set client-side during `.map()` transformation

---

## SF-10: Confirmation Dialog (LWC) {#confirmation-dialog}

Delete confirmation using `LightningConfirm` followed by imperative Apex, toast feedback, and data refresh.

```javascript
import LightningConfirm from 'lightning/confirm';
import Toast from 'lightning/toast';
import deleteRecord from '@salesforce/apex/MyController.deleteRecord';

async handleDelete(row) {
    const confirmed = await LightningConfirm.open({
        message: `Are you sure you want to delete "${row.Name}"? This action cannot be undone.`,
        variant: 'header',
        label: 'Delete Record'
    });

    if (!confirmed) {
        return;
    }

    this.isLoading = true;
    try {
        await deleteRecord({ recordId: row.Id });
        Toast.show({
            label: 'Record deleted successfully.',
            mode: 'dismissible',
            variant: 'success'
        }, this);
        this.refreshData();
    } catch (error) {
        this.isLoading = false;
        Toast.show({
            label: error?.body?.message || 'An error occurred while deleting the record.',
            mode: 'sticky',
            variant: 'error'
        }, this);
    }
}
```

**Rules**:
- Always confirm before destructive operations — never delete on a single click
- Include the record name or identifier in the confirmation message
- Set `isLoading = true` **after** confirmation, not before — don't show a spinner while the dialog is open
- On success: show toast, then refresh data (the refresh will clear `isLoading`)
- On error: clear `isLoading` immediately, show sticky error toast
- The Apex `deleteRecord` method should validate ownership/permissions, use `AccessLevel.USER_MODE`, and throw `AuraHandledException` on failure

---

## SF-11: Filter Whitelist Validation (Apex) {#filter-whitelist}

Server-side validation of user-supplied field names in dynamic SOQL to prevent field injection.

```apex
public with sharing class MyController {

    private static final Set<String> ALLOWED_SORT_FIELDS = new Set<String>{
        'Name', 'CreatedDate', 'Email', 'Status__c'
    };

    private static final Set<String> ALLOWED_FILTER_FIELDS = new Set<String>{
        'Status__c', 'Type__c', 'OwnerId'
    };

    @AuraEnabled(cacheable=true)
    public static List<Contact> getRecords(String sortedBy, String sortedDirection, List<String> filterBy) {
        String query = 'SELECT Id, Name, Email FROM Contact WHERE AccountId != null';

        for (String filterField : filterBy) {
            List<String> parts = filterField.split(':');
            if (parts.size() == 2 && ALLOWED_FILTER_FIELDS.contains(parts[0])) {
                query += ' AND ' + parts[0] + ' = :filterValue';
            }
        }

        if (sortedBy != null && ALLOWED_SORT_FIELDS.contains(sortedBy)) {
            query += ' ORDER BY ' + sortedBy;
            query += (sortedDirection == 'asc') ? ' ASC' : ' DESC';
            query += ' NULLS LAST';
        } else {
            query += ' ORDER BY Name ASC NULLS LAST';
        }

        return Database.query(query);
    }
}
```

**Rules**:
- **Never trust field names from the client** — `String.escapeSingleQuotes()` only prevents value injection, not field/object injection
- Define `private static final Set<String>` constants for every dynamic field position (ORDER BY, WHERE field names, GROUP BY)
- If the field name is not in the whitelist, fall back to a safe default — do not throw an error (the LWC may send stale column names after a schema change)
- Sort direction should be validated with a ternary (`== 'asc' ? 'ASC' : 'DESC'`), never concatenated directly
- Bind variables (`:paramName`) remain the correct approach for **values** in WHERE clauses — whitelists are for **field names**

---

## SF-12: Apex Inline Documentation {#apex-docs}

ApexDoc and inline comment standards.

### Class-level ApexDoc

Required on every public class. One sentence describing purpose. If `without sharing`, include justification.

```apex
/**
 * @description Provides paginated data for the MyComponent LWC.
 * Uses without sharing to allow cross-org visibility for all users.
 */
public without sharing class MyController {
    // ...
}
```

### Method-level ApexDoc

Required on `@AuraEnabled` and public methods. Include `@description`, `@param`, and `@return`.

```apex
/**
 * @description Returns paginated results based on view type.
 * @param pageSize Number of records per page
 * @param pageNumber Current page (1-based)
 * @param viewType Filter mode
 * @return Wrapper containing records and total count
 */
@AuraEnabled(cacheable=true)
public static MyWrapper getData(Integer pageSize, Integer pageNumber, String viewType) {
    // ...
}
```

Not required on private helpers unless the logic is non-obvious. A `buildWrapper()` that maps fields needs no doc; a `buildFilterQuery()` that constructs dynamic SOQL with escaping does.

### Wrapper / DTO class ApexDoc

Brief `@description` on inner classes explaining the data they carry.

```apex
/** @description Hierarchical response: parent records with nested children. */
public class MyWrapper {
    @AuraEnabled public List<ItemWrapper> items;
    @AuraEnabled public Integer totalCount;
}
```

### Inline comments

Required only where the *why* isn't obvious from the code:

```apex
// Dynamic SOQL: subquery is required because Account has no direct flag —
// the relationship comes via Contact.IsMember__c
String baseFilter = 'Id IN (SELECT AccountId FROM Contact WHERE IsMember__c = true)';
```

Do **not** restate the code:
```apex
// NO — self-explanatory
wrapper.totalCount = totalCount;
```

**Rules**:
- Class-level ApexDoc: required on every public/global class
- Method-level ApexDoc: required on `@AuraEnabled` and public methods; optional on private methods
- Wrapper ApexDoc: one-line `@description` on each inner class
- Inline comments: only for non-obvious logic — dynamic SOQL construction, permission checks, governor-limit workarounds, business rules with external context
- Do not document test classes — test method names should be self-documenting via `test{Method}_{scenario}` convention
- Use `@description` (lowercase) consistently — ApexDoc standard

---

## SF-13: LWC Inline Documentation {#lwc-docs}

JSDoc, HTML comments, and meta XML description standards.

### Class-level JSDoc

```javascript
/**
 * Displays a hierarchical accordion of organizations, contacts, and devices.
 */
export default class MyListComponent extends NavigationMixin(LightningElement) {
    // ...
}
```

### @api property JSDoc

Required on every `@api` property — these are the public contract.

```javascript
/** @type {string} Title shown in the modal header. */
@api modalTitle = 'About';

/** @type {string} Salesforce record ID, set automatically on record pages. */
@api recordId;
```

### Method JSDoc

Required on event handlers that aren't self-explanatory and any method over ~30 lines. Not required on simple getters, lifecycle hooks, or one-liner handlers.

```javascript
/**
 * Builds CSV content from current page data with TLP header line,
 * then triggers a download via hidden anchor element.
 */
handleExportCSV() {
    // ...
}
```

Not needed:
```javascript
// NO — handler name + one line of logic makes this obvious
handleViewChange(event) {
    this.viewType = event.target.value;
    this.page = 1;
    this.fetchData();
}
```

### HTML section comments

Use `<!-- Section Name -->` markers for major template regions.

```html
<template>
    <!-- Hidden CSV download anchor -->
    <a data-id="csvDownloadLink" style="display:none;"></a>

    <div class="container">
        <!-- Header Card -->
        <article class="slds-card slds-m-bottom_medium">...</article>

        <!-- Main Content -->
        <template lwc:if={hasAccess}>...</template>

        <!-- Access Denied State -->
        <template lwc:else>...</template>
    </div>
</template>
```

### Meta XML description

Add a `<description>` element to `.js-meta.xml` — one sentence matching the Purpose line from the component's doc file.

### Inline comments

Same principle as Apex — comment the *why*, not the *what*.

**Rules**:
- Class-level JSDoc: required on every exported component class
- `@api` JSDoc: required on every `@api` property — include `@type` and a description
- Method JSDoc: required on complex or long (30+ line) methods; skip for obvious handlers and getters
- HTML comments: section markers for major regions; not for every conditional block
- Meta XML `<description>`: required — one sentence
- Do not add comments that restate the code

---

## SF-14: LWC Jest Test Structure {#jest-tests}

Standard structure for Jest unit tests of LWC components. Tests go in `force-app/main/default/lwc/{componentName}/__tests__/{componentName}.test.js`.

### Test File Setup

```javascript
import { createElement } from 'lwc';
import MyComponent from 'c/myComponent';
import getActiveRecord from '@salesforce/apex/MyController.getActiveRecord';

// Mock Apex wire adapter
jest.mock(
    '@salesforce/apex/MyController.getActiveRecord',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// Mock LMS (if component subscribes)
jest.mock('lightning/messageService', () => ({
    subscribe: jest.fn(),
    unsubscribe: jest.fn(),
    publish: jest.fn(),
    MessageContext: jest.fn()
}), { virtual: true });
```

### Helper: Create Component

```javascript
async function createComponent(props = {}) {
    const element = createElement('c-my-component', { is: MyComponent });
    Object.assign(element, props);
    document.body.appendChild(element);
    await Promise.resolve(); // Flush microtasks so @wire resolves
    return element;
}
```

### Test: Wire Data Renders

```javascript
describe('c-my-component', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders content when wire returns data', async () => {
        getActiveRecord.mockResolvedValue({
            Title__c: 'Hello',
            Body__c: 'World'
        });

        const element = await createComponent();

        const title = element.shadowRoot.querySelector('h1');
        expect(title).not.toBeNull();
        expect(title.textContent).toBe('Hello');
    });
});
```

### Test: Wire Error / Loading State

```javascript
it('shows error state when wire fails', async () => {
    getActiveRecord.mockRejectedValue(new Error('Server error'));
    const element = await createComponent();
    const errorMsg = element.shadowRoot.querySelector('[data-id="error-message"]');
    expect(errorMsg).not.toBeNull();
});

it('shows spinner while data loads', async () => {
    getActiveRecord.mockImplementation(() => new Promise(() => {}));
    const element = await createComponent();
    const spinner = element.shadowRoot.querySelector('lightning-spinner');
    expect(spinner).not.toBeNull();
});
```

### Test: User Interaction

```javascript
it('fires event when button clicked', async () => {
    getActiveRecord.mockResolvedValue({ Title__c: 'Test' });
    const element = await createComponent();

    const handler = jest.fn();
    element.addEventListener('myaction', handler);

    const button = element.shadowRoot.querySelector('lightning-button');
    button.click();

    expect(handler).toHaveBeenCalledTimes(1);
});
```

### Test: LMS Subscription

```javascript
import { subscribe } from 'lightning/messageService';
import myChannel from '@salesforce/messageChannel/My_Channel__c';

jest.mock('@salesforce/messageChannel/My_Channel__c', () => ({ default: jest.fn() }), { virtual: true });

it('subscribes on connect', async () => {
    const element = await createComponent();
    expect(subscribe).toHaveBeenCalledWith(
        expect.anything(),
        myChannel,
        expect.any(Function)
    );
});
```

**Rules**:
- File location: `{paths.lwcSource}/{componentName}/__tests__/{componentName}.test.js`
- Always clean up DOM in `afterEach` — remove all child elements and clear mocks
- Mock all Apex imports with `jest.mock()` and `{ virtual: true }`
- Mock LMS (`lightning/messageService`) if the component subscribes to any channel
- Use `await Promise.resolve()` after `appendChild` to flush microtasks and let `@wire` resolve
- Test four states minimum: **data loaded**, **error**, **loading**, and **user interaction**
- Use `shadowRoot.querySelector` for DOM assertions (LWC uses shadow DOM)
- Run with the unit-test command from `.claude/sf-project.json` (`quality.unitTestCommand`)

---

## SF-15: HTTP Callout via Named Credential (Apex) {#callout-named-credential}

Always make outbound HTTP callouts through a **Named Credential**. Never hardcode endpoints or credentials in Apex.

```apex
public with sharing class OrderApiClient {

    private static final String NAMED_CREDENTIAL = 'callout:Acme_Order_API';

    public static OrderResponse fetchOrder(String orderId) {
        if (String.isBlank(orderId)) {
            throw new IllegalArgumentException('orderId is required');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/orders/' + EncodingUtil.urlEncode(orderId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(30000);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            Logger.log('OrderApiClient.fetchOrder failed: ' + res.getStatusCode() + ' ' + res.getBody());
            throw new CalloutException('Order API returned ' + res.getStatusCode());
        }

        return (OrderResponse) JSON.deserialize(res.getBody(), OrderResponse.class);
    }

    public class OrderResponse {
        public String id;
        public String status;
        public Decimal total;
    }
}
```

**Rules**:
- Use the `callout:<NamedCredential>` URL prefix — Salesforce injects auth at runtime
- Set explicit `setTimeout` (default 10s, max 120s) — long callouts hold up the transaction
- Validate inputs before issuing the callout (governor limits still apply on failure)
- URL-encode any path segments built from user input
- Log unexpected status codes via the project's `Logger` before throwing
- For tests: implement `Test.setMock(HttpCalloutMock.class, new YourMock());` — see SF-16 example for the mock shape
- Per-transaction limit: 100 callouts (sync), aggregate timeout 120s

## SF-16: Apex REST Service {#apex-rest-service}

Public REST endpoint exposed at `/services/apexrest/<urlMapping>/`. One method per HTTP verb. Shared error-envelope wrapper.

```apex
@RestResource(urlMapping='/orders/*')
global with sharing class OrderRestService {

    @HttpGet
    global static Response doGet() {
        try {
            String orderId = idFromRequestUri();
            Order__c o = [
                SELECT Id, Name, Status__c, Total_Amount__c
                FROM Order__c
                WHERE Id = :orderId
                WITH USER_MODE
                LIMIT 1
            ];
            return success(new OrderDto(o));
        } catch (QueryException e) {
            return notFound('Order not found');
        } catch (Exception e) {
            Logger.log('OrderRestService.doGet: ' + e);
            return serverError(e.getMessage());
        }
    }

    @HttpPost
    global static Response doPost(OrderDto body) {
        try {
            if (body == null || String.isBlank(body.status)) {
                return badRequest('status is required');
            }
            Order__c o = new Order__c(
                Name = body.name,
                Status__c = body.status,
                Total_Amount__c = body.total
            );
            insert as user o;
            return success(new OrderDto(o));
        } catch (DmlException e) {
            return badRequest(e.getDmlMessage(0));
        } catch (Exception e) {
            Logger.log('OrderRestService.doPost: ' + e);
            return serverError(e.getMessage());
        }
    }

    // ---- shared envelope ----------------------------------------------------

    global class Response {
        global Boolean success;
        global OrderDto data;
        global String error;
        global Integer status;
    }

    global class OrderDto {
        global String id;
        global String name;
        global String status;
        global Decimal total;
        global OrderDto() {}
        global OrderDto(Order__c o) {
            this.id = o.Id;
            this.name = o.Name;
            this.status = o.Status__c;
            this.total = o.Total_Amount__c;
        }
    }

    private static String idFromRequestUri() {
        RestRequest req = RestContext.request;
        return req.requestURI.substringAfterLast('/');
    }

    private static Response success(OrderDto d)        { return build(true,  d, null,  200); }
    private static Response badRequest(String msg)     { return build(false, null, msg, 400); }
    private static Response notFound(String msg)       { return build(false, null, msg, 404); }
    private static Response serverError(String msg)    { return build(false, null, msg, 500); }
    private static Response build(Boolean ok, OrderDto d, String err, Integer status) {
        RestContext.response.statusCode = status;
        Response r = new Response();
        r.success = ok; r.data = d; r.error = err; r.status = status;
        return r;
    }
}
```

**Test mock for SF-15 callouts**:

```apex
@isTest
private class OrderApiClientTest {
    private class OrderMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"O-1","status":"OPEN","total":42.0}');
            return res;
        }
    }
    @isTest static void fetchOrder_returnsParsedResponse() {
        Test.setMock(HttpCalloutMock.class, new OrderMock());
        Test.startTest();
        OrderApiClient.OrderResponse r = OrderApiClient.fetchOrder('O-1');
        Test.stopTest();
        System.assertEquals('OPEN', r.status, 'status from mock body');
    }
}
```

**Rules**:
- `global` is required for the class and exposed methods (Apex REST contract)
- One method per HTTP verb; pull path/query params from `RestContext.request`
- Use `with sharing` and `WITH USER_MODE` / `as user` DML — REST services bypass UI sharing if you don't
- Wrap responses in a uniform envelope so clients can parse success/error consistently
- Set `RestContext.response.statusCode` explicitly — don't rely on Apex defaults
- Validate input before DML; return 400 for bad input, 500 only for unexpected errors
- Test with `Test.startTest()` / `Test.stopTest()` boundaries; use `Test.setMock` for any callouts the service makes downstream

## SF-17: Custom Metadata Type Lookup {#custom-metadata-lookup}

Read configuration from Custom Metadata Types (`__mdt`) — never hardcode org-specific values like emails, URLs, feature flags, or thresholds. Cache lookups in a static map for transaction reuse.

```apex
public with sharing class FeatureFlags {

    private static Map<String, Feature_Flag__mdt> cache;

    public static Boolean isEnabled(String developerName) {
        ensureLoaded();
        Feature_Flag__mdt f = cache.get(developerName);
        return f != null && f.Enabled__c == true;
    }

    public static String getValue(String developerName) {
        ensureLoaded();
        Feature_Flag__mdt f = cache.get(developerName);
        return f == null ? null : f.Value__c;
    }

    @TestVisible
    private static void load(List<Feature_Flag__mdt> rows) {
        cache = new Map<String, Feature_Flag__mdt>();
        for (Feature_Flag__mdt r : rows) cache.put(r.DeveloperName, r);
    }

    private static void ensureLoaded() {
        if (cache != null) return;
        load([
            SELECT DeveloperName, Enabled__c, Value__c
            FROM Feature_Flag__mdt
        ]);
    }
}
```

**Test**:

```apex
@isTest
private class FeatureFlagsTest {
    @isTest static void isEnabled_respectsMockData() {
        Feature_Flag__mdt f = new Feature_Flag__mdt(DeveloperName = 'NEW_UI', Enabled__c = true);
        FeatureFlags.load(new List<Feature_Flag__mdt>{ f });

        Test.startTest();
        System.assertEquals(true, FeatureFlags.isEnabled('NEW_UI'), 'flag should be on');
        System.assertEquals(false, FeatureFlags.isEnabled('UNKNOWN'), 'missing flag should be off');
        Test.stopTest();
    }
}
```

**Rules**:
- Custom Metadata queries do **not** count against SOQL governor limits — but still cache in a static map to avoid repeating the lookup
- Use `@TestVisible` on a `load(List<...>)` setter so tests inject mock data without needing real metadata records
- Don't use Custom Settings for new config — Custom Metadata Types are deployable and migration-friendly
- For high-cardinality lookups (>200 rows), index by the lookup key; for small enums use a direct `Map<DeveloperName, Record>`
- Reference field metadata via `__c` suffix; `MasterLabel` and `DeveloperName` are standard

## SF-18: LWC Internationalization (i18n) {#lwc-i18n}

Use `@salesforce/i18n/*` modules and Custom Labels for any user-visible strings. Never hardcode strings in HTML templates or JS. Format dates, numbers, and currency with the platform's locale-aware formatters.

```javascript
import { LightningElement } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import TIMEZONE from '@salesforce/i18n/timeZone';
import LABEL_GREETING from '@salesforce/label/c.Greeting';
import LABEL_TOTAL from '@salesforce/label/c.Order_Total';

export default class OrderSummary extends LightningElement {
    @api order;

    label = { greeting: LABEL_GREETING, total: LABEL_TOTAL };

    get formattedTotal() {
        return new Intl.NumberFormat(LOCALE, {
            style: 'currency',
            currency: CURRENCY
        }).format(this.order.total);
    }

    get formattedDate() {
        return new Intl.DateTimeFormat(LOCALE, {
            dateStyle: 'medium',
            timeZone: TIMEZONE
        }).format(new Date(this.order.placedAt));
    }
}
```

```html
<template>
  <p>{label.greeting}</p>
  <p>{label.total}: {formattedTotal}</p>
  <p>{formattedDate}</p>
</template>
```

**Rules**:
- All user-visible strings come from Custom Labels: `import LBL from '@salesforce/label/c.My_Label'`
- Pluralization, dates, currencies → use `Intl.*` with `LOCALE` from `@salesforce/i18n/locale`
- Right-to-left (RTL) support: use SLDS direction-aware utilities (`slds-m-end_*` instead of `slds-m-right_*`); avoid hardcoded `left:`/`right:` in CSS
- Use `<lightning-formatted-number>`, `<lightning-formatted-date-time>`, `<lightning-formatted-rich-text>` instead of manual string interpolation when possible
- Server-side messages thrown via `AuraHandledException` are not auto-translated — pass a Custom Label key from Apex when you need translated error messages: `throw new AuraHandledException(System.Label.Order_Not_Found);`

## SF-19: Virtualized List for Large Datasets (LWC) {#lwc-virtualized-list}

Rendering more than ~500 rows in a single template is a render-time bottleneck. For large lists, virtualize: render only the visible window plus a buffer.

```javascript
import { LightningElement, api } from 'lwc';

const ROW_HEIGHT = 36;
const BUFFER = 5;

export default class VirtualList extends LightningElement {
    @api items = [];
    @api itemTemplate;

    scrollTop = 0;
    viewportHeight = 0;

    connectedCallback() {
        this.viewportHeight = 480;
    }

    handleScroll(event) {
        this.scrollTop = event.target.scrollTop;
    }

    get visibleItems() {
        const start = Math.max(0, Math.floor(this.scrollTop / ROW_HEIGHT) - BUFFER);
        const end = Math.min(
            this.items.length,
            Math.ceil((this.scrollTop + this.viewportHeight) / ROW_HEIGHT) + BUFFER
        );
        return this.items.slice(start, end).map((item, i) => ({
            ...item,
            _y: (start + i) * ROW_HEIGHT
        }));
    }

    get totalHeight() {
        return this.items.length * ROW_HEIGHT;
    }
}
```

**Rules**:
- Trigger virtualization only when `items.length > ~500` — for small lists, plain templates are simpler and faster
- For built-in datatable use cases, prefer `lightning-datatable` with pagination (SF-1) over a custom virtualized list — the platform component has accessibility and column resize built in
- Keep row height fixed; variable-height virtualization needs additional measurement passes
- Avoid wiring `@wire` to the visible window — load all data first, then virtualize the render

## SF-20: Lazy-Loaded Sub-component (LWC) {#lwc-lazy-load}

Use `lwc:if` + dynamic import for heavy panels (rich-text editors, charts, large modals) so the main bundle stays small.

```javascript
import { LightningElement, track } from 'lwc';

export default class LazyContainer extends LightningElement {
    @track showEditor = false;
    @track editorLoaded = false;

    async openEditor() {
        if (!this.editorLoaded) {
            await import('c/richTextEditor');
            this.editorLoaded = true;
        }
        this.showEditor = true;
    }
}
```

```html
<template>
  <lightning-button label="Edit" onclick={openEditor}></lightning-button>
  <template lwc:if={showEditor}>
    <c-rich-text-editor></c-rich-text-editor>
  </template>
</template>
```

**Rules**:
- Dynamic imports are only useful for components that pull in non-trivial dependencies (charts, editors, third-party libs)
- Once loaded, stays loaded for the page lifecycle — use a flag like `editorLoaded` to avoid redundant `await import(...)` calls
- Combine with `lwc:if` to keep the heavy DOM out of the initial render
- Don't lazy-load components that are likely to render on first paint — the deferral hurts perceived performance
