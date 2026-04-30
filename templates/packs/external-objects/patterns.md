## EXT-1: Picking the Adapter (OData 4.0 / Cross-Org / Custom Apex) {#ext-adapter}

Salesforce Connect surfaces external data as `__x` objects with no local replication. Three built-in adapters; pick by source system and read/write needs.

| Adapter | Source | Reads | Writes | Cost & limits |
|---------|--------|-------|--------|---------------|
| **OData 4.0** | Any OData v4 service (SAP, MS Dynamics, .NET endpoints) | ✅ | ✅ (write-back enabled per object) | Per-callout governor; no row count cap; no SOQL pagination caching |
| **OData 2.0** | Legacy OData v2 services | ✅ | ⚠️ Limited write semantics | Same as v4 plus type-coercion gotchas |
| **Cross-Org** | Another Salesforce org | ✅ | ❌ (read-only) | OAuth + Connected App; respects source-org sharing |
| **Custom Apex Connector** | Anything else (REST, SOAP, gRPC) | ✅ | ✅ if implemented | You write the adapter; full control + full responsibility |

The metadata layer is identical regardless of adapter — choose first, then define the External Data Source and `__x` objects.

```xml
<!-- force-app/main/default/dataSources/ERP_OData.dataSource-meta.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<ExternalDataSource xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>ERP OData</label>
    <type>OData4</type>
    <endpoint>https://erp.example.com/odata/v4/</endpoint>
    <protocol>Oauth</protocol>
    <namedCredential>ERP_System</namedCredential>
    <isWritable>true</isWritable>
</ExternalDataSource>
```

**Rules**:
- **Always go through a Named Credential** (SF-15). Embedding endpoints/secrets in the data-source metadata is a deploy-time leak waiting to happen
- **Pick OData 4 over OData 2** when both are available — better cardinality semantics, native expand support, OAuth that survives token rotation
- **Cross-Org adapter is read-only.** If the consumer needs to write back, model the write as an Apex callout to the source org's REST surface; don't try to fake write-through
- **Build a Custom Apex Connector when the source isn't OData and you can't add OData in front of it.** It's more work but it's the only path for SOAP, gRPC, and other non-REST shapes

## EXT-2: Defining the External Object and Sync Schema {#ext-define}

External Objects (`__x`) live in metadata like custom objects but resolve their data from the external system at query time. Field names and types must match the external schema; Salesforce coerces on read.

```xml
<!-- force-app/main/default/objects/Erp_Order__x/Erp_Order__x.object-meta.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <deploymentStatus>Deployed</deploymentStatus>
    <label>ERP Order</label>
    <pluralLabel>ERP Orders</pluralLabel>
    <externalDataSource>ERP_OData</externalDataSource>
    <externalRepository>Orders</externalRepository>
    <enableSearch>true</enableSearch>
</CustomObject>
```

```xml
<!-- force-app/main/default/objects/Erp_Order__x/fields/Order_Number__c.field-meta.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Order_Number__c</fullName>
    <externalId>true</externalId>
    <label>Order Number</label>
    <length>50</length>
    <required>true</required>
    <type>Text</type>
    <unique>true</unique>
</CustomField>
```

```xml
<!-- Indirect Lookup: relate Erp_Order__x to local Account by external id -->
<!-- force-app/main/default/objects/Erp_Order__x/fields/Account__c.field-meta.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Account__c</fullName>
    <label>Account</label>
    <referenceTo>Account</referenceTo>
    <relationshipName>Erp_Orders</relationshipName>
    <relationshipLabel>ERP Orders</relationshipLabel>
    <externalRelationshipName>External_Account_Id__c</externalRelationshipName>
    <type>IndirectLookup</type>
</CustomField>
```

**Rules**:
- **Mark exactly one field as the external id** (`<externalId>true</externalId>`) per External Object. SOQL queries resolve `Id` → that field
- **Use Indirect Lookup over Lookup** when relating an External Object to a standard sObject through a non-Salesforce key
- **Use External Lookup** when relating two External Objects from the same data source
- **Keep field names aligned with the source schema.** Mismatches force a transformation layer in the adapter; better to mirror the source and rename in the UI label
- **`enableSearch` only when the adapter supports it.** OData 4 with `$search` works; bare REST adapters fall back to in-memory filter, which is slow

## EXT-3: Apex Querying with Pagination and Caching {#ext-query}

Querying an External Object is just SOQL syntactically, but every query is a live callout to the source. Pagination lives in the adapter; result caching is opt-in via the data source's `customConfiguration` or via Lightning Platform Cache layered on top.

```apex
public with sharing class ErpOrderClient {

    /** Live query — every call is a callout. Bound by source-system rate limits. */
    public static List<Erp_Order__x> findRecent(Id accountId, Integer limitN) {
        // SOQL on __x objects supports a subset of standard predicates; check
        // the adapter's documented capabilities before adding ORDER BY or aggregations
        return [
            SELECT Order_Number__c, Status__c, Total__c, Created_Date__c
            FROM Erp_Order__x
            WHERE Account__r.Id = :accountId
            ORDER BY Created_Date__c DESC
            LIMIT :limitN
        ];
    }

    /** Cached read — wrap the live query in @AuraEnabled cacheable for short-lived
     *  read-mostly workloads. Cache TTL is the LWC's wire-cache lifetime; for
     *  durable caching across users, use Platform Cache. */
    @AuraEnabled(cacheable=true)
    public static List<Erp_Order__x> getRecent(Id accountId) {
        return findRecent(accountId, 50);
    }

    /** Force-refresh path for "I just wrote — give me current" cases. */
    @AuraEnabled
    public static List<Erp_Order__x> getRecentFresh(Id accountId) {
        return findRecent(accountId, 50);
    }
}
```

**Rules**:
- **Every query is a callout.** Callout governor limits apply (100 sync per transaction). Don't wire a list view straight at a high-traffic External Object
- **Pagination is OData-managed for OData adapters.** SOQL `LIMIT` translates to `$top`; offset to `$skip`. Custom Apex Connectors have to implement pagination themselves
- **Use `cacheable=true`** for read-mostly LWC patterns. The LWC `@wire` cache de-duplicates within a session
- **Layer Platform Cache** for cross-user shared reads (e.g., a product catalog). 5 min TTL is a reasonable default; longer for slow-changing data
- **Indirect Lookup joins are expensive.** Each `__r` traversal can become its own callout. Project the external id into the query and resolve in Apex when ergonomics permits

## EXT-4: Writes and Write-Back Semantics {#ext-writeback}

OData 4 with `isWritable = true` allows DML on External Objects. Inserts go to the source system; updates round-trip; deletes are HTTP DELETE. Custom Apex Connectors decide their own write semantics — implement the writable interface to opt in.

```apex
public class ErpOrderWriter {

    /** Insert into the external ERP — round-trips through the connector. */
    public static Id createOrder(Erp_Order__x stub) {
        if (stub.Order_Number__c == null) {
            throw new IllegalArgumentException('Order_Number__c required');
        }
        // DML on External Objects looks identical to standard DML
        insert as user stub;
        // The returned Id is the synthesized external Id — survives across queries
        return stub.Id;
    }

    /** Bulk update — adapter chunks per its config; DML governor counts each row. */
    public static void updateStatuses(Map<Id, String> statusByExternalId) {
        List<Erp_Order__x> updates = new List<Erp_Order__x>();
        for (Id extId : statusByExternalId.keySet()) {
            updates.add(new Erp_Order__x(Id = extId, Status__c = statusByExternalId.get(extId)));
        }
        update as user updates;
    }
}
```

**Rules**:
- **External writes are not transactional with local DML.** A Salesforce transaction that updates an `__c` and an `__x` together can succeed locally and fail externally — handle the partial-failure path explicitly
- **Use `as user`** to inherit the running user's CRUD/FLS. External Objects honor those just like local objects
- **Test the write-back contract** in a sandbox against a non-production source system. Every external system has its own mutation quirks (idempotency, optimistic concurrency, partial-batch semantics)
- **Don't write from a `before` trigger.** External callouts in `before` triggers are forbidden; use `after` plus a Queueable for write-back
- **Catch `CalloutException` separately from `DmlException`** — the failure modes are very different (timeout vs. validation) and the recovery path differs

## EXT-5: Custom Apex Connector for Non-OData Sources {#ext-apex-connector}

For sources that aren't OData (SOAP, REST not OData-shaped, gRPC, files), implement a Custom Apex Connector by extending `DataSource.Connection`. You handle the metadata sync, query translation, and (optionally) write-back yourself.

```apex
global class LegacyOrderConnector extends DataSource.Connection {

    /** Define the schema Salesforce will materialize as __x objects. */
    override global List<DataSource.Table> sync() {
        DataSource.Table t = DataSource.Table.get('Order', 'Order_Number__c', new List<DataSource.Column>{
            DataSource.Column.text('Order_Number__c', 50),
            DataSource.Column.text('Status__c', 40),
            DataSource.Column.number('Total__c', 18, 2),
            DataSource.Column.url('ExternalId'),
            DataSource.Column.url('DisplayUrl')
        });
        t.labelPlural = 'Orders';
        return new List<DataSource.Table>{ t };
    }

    /** Translate SOQL to the source system's query API. */
    override global DataSource.TableResult query(DataSource.QueryContext ctx) {
        // Pull predicates from ctx.tableSelection.filter
        // Issue HTTP callout to the legacy system
        // Return DataSource.TableResult with rows + total count
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Legacy_Orders/query');
        req.setMethod('POST');
        req.setBody(buildPayload(ctx));
        HttpResponse res = new Http().send(req);

        List<Map<String, Object>> rows = parseRows(res.getBody());
        return DataSource.TableResult.get(ctx, rows);
    }

    private String buildPayload(DataSource.QueryContext ctx) { /* … */ return ''; }
    private List<Map<String, Object>> parseRows(String body)  { /* … */ return null; }
}
```

The provider class registers the connector type:

```apex
global class LegacyOrderProvider extends DataSource.Provider {
    override global List<DataSource.AuthenticationCapability> getAuthenticationCapabilities() {
        return new List<DataSource.AuthenticationCapability>{
            DataSource.AuthenticationCapability.OAUTH
        };
    }
    override global List<DataSource.Capability> getCapabilities() {
        return new List<DataSource.Capability>{
            DataSource.Capability.ROW_QUERY,
            DataSource.Capability.SEARCH
        };
    }
    override global DataSource.Connection getConnection(DataSource.ConnectionParams params) {
        return new LegacyOrderConnector();
    }
}
```

**Rules**:
- **Implement only the capabilities you'll honor.** Listing `ROW_UPDATE` without supporting it surfaces confusing errors at write time
- **Honor `ctx.tableSelection.filter` precisely.** Anything in the filter that you don't translate becomes "fetch everything and filter in Apex" — slow and expensive
- **Cap result sets in the connector.** Source systems with no native pagination need a hard ceiling enforced before returning to Salesforce
- **Cache schema reasonably.** `sync()` is called on metadata refresh; don't make it an expensive runtime call from Apex
- **Test with the OData simulator first.** Build against the OData adapter to validate the schema, then re-implement in Apex once the contract is stable

---

## Anti-patterns

- **Replicating External Object data into local custom objects "for performance."** That defeats the purpose of Salesforce Connect. If you need local data, use Bulk API ETL — but if you need *live* data, accept the callout cost
- **Embedding endpoints in the data-source metadata.** Always Named Credential. Configuration changes shouldn't require re-deploys
- **Wiring an External Object straight to a high-traffic list view.** Every page load is a callout. Cache, paginate, or pre-aggregate to a custom object instead
- **Marking everything as `enableSearch`.** Search on adapters that don't support `$search` falls back to row-by-row filter — disastrous for large external sets
- **Mixing local and external writes in one Apex transaction without partial-failure handling.** External writes don't roll back when local DML fails; design for the divergent state
- **Building a Custom Apex Connector for a system that has OData support.** Re-implementing OData inside Apex is an anti-pattern. Use the platform adapter
- **Querying External Objects from a `before` trigger.** External Objects do callouts; callouts in `before` triggers are forbidden. Move the read to `after` or to a service class invoked async
