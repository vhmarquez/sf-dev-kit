## BIG-1: Defining a Big Object {#big-define}

A Big Object stores billions of records on a separate, immutable index — no triggers, no validation rules, no sharing rules, no standard SOQL. It's append-only by design. Define it in metadata; choose the index fields carefully because **the index is the only way to query the data** and it cannot be changed after deploy.

```xml
<!-- force-app/main/default/objects/Order_Audit__b/Order_Audit__b.object-meta.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <deploymentStatus>Deployed</deploymentStatus>
    <label>Order Audit</label>
    <pluralLabel>Order Audits</pluralLabel>
    <indexes>
        <fullName>OrderAuditIdx</fullName>
        <label>Order Audit Index</label>
        <fields>
            <name>Order_Id__c</name>
            <sortDirection>ASC</sortDirection>
        </fields>
        <fields>
            <name>Captured_At__c</name>
            <sortDirection>DESC</sortDirection>
        </fields>
    </indexes>
</CustomObject>
```

Each indexed field also exists as a CustomField with `<type>Text</type>` (or `DateTime`, `Number` — the supported types are limited).

**Rules**:
- **Pick the index for your query, not your data shape.** A query must filter on the leading index field (`Order_Id__c` here); subsequent fields can only be filtered when the prior fields are equality-filtered or omitted from the predicate
- **The index is permanent.** Adding/removing index fields is a destructive change — it requires creating a new Big Object and re-loading
- **Big Objects are not transactional.** Inserts are eventual; reads can return slightly stale results during the index propagation window (~minutes)
- **No relationships, no triggers, no sharing.** Big Objects sit outside those models. Access control is profile/permset CRUD on the object
- **Storage doesn't count toward standard data limits.** That's the whole point — they're for archival and audit data that would blow standard storage

## BIG-2: Inserting via Apex (Bulk-Safe) {#big-insert}

Use `Database.insertImmediate()` for sync writes (≤ 200 rows) or load via Bulk API 2.0 for high volume. The standard `insert` keyword does not work on Big Objects.

```apex
public with sharing class OrderAuditWriter {

    /** Sync write — for small batches inside a transaction. Up to 200 rows. */
    public static void appendSync(List<Order_Audit__b> rows) {
        if (rows.isEmpty()) return;
        if (rows.size() > 200) {
            throw new IllegalArgumentException('Use Bulk API for >200 rows');
        }

        // insertImmediate is the only sync write API for Big Objects
        Database.insertImmediate(rows);
    }

    /** Async write from a trigger or Queueable — uses Bulk API 2.0 under the hood. */
    public static void appendAsync(List<Order__c> orders) {
        List<Order_Audit__b> rows = new List<Order_Audit__b>();
        for (Order__c o : orders) {
            rows.add(new Order_Audit__b(
                Order_Id__c   = o.Id,
                Captured_At__c = Datetime.now(),
                Status__c     = o.Status__c,
                Total__c      = o.Total_Amount__c
            ));
        }
        if (!rows.isEmpty()) {
            System.enqueueJob(new BigObjectWriterQueueable(rows));
        }
    }
}

public class BigObjectWriterQueueable implements Queueable, Database.AllowsCallouts {
    private List<Order_Audit__b> rows;
    public BigObjectWriterQueueable(List<Order_Audit__b> rows) { this.rows = rows; }

    public void execute(QueueableContext ctx) {
        // insertImmediate works in a Queueable; chain if rows > 200
        for (Integer i = 0; i < rows.size(); i += 200) {
            List<Order_Audit__b> chunk = new List<Order_Audit__b>();
            for (Integer j = i; j < Math.min(i + 200, rows.size()); j++) {
                chunk.add(rows[j]);
            }
            Database.insertImmediate(chunk);
        }
    }
}
```

**Rules**:
- **`Database.insertImmediate`, not `insert`.** Standard DML throws on Big Objects
- **Inserts are append-only.** There is no update or delete via Apex — to remove rows, drop and recreate the Big Object (requires a destructive change deploy)
- **Use the index in lookup before write.** Big Objects are eventual-consistency on read, but the index dedups on the composite key — duplicate inserts on the same index value silently overwrite the row (which is the intended "upsert" behavior)
- **Bulk API 2.0 is the path for >10K rows per batch.** Apex Queueable is fine for steady-state writes; use Bulk for backfill loads

## BIG-3: Async SOQL for Aggregation {#big-async-soql}

Standard SOQL on Big Objects returns up to 50,000 rows synchronously, with hard restrictions on the WHERE clause. For analytical queries (counts, aggregations, joins to standard objects), use **Async SOQL** which returns results to a target sObject instead of in-memory.

```apex
public class OrderAuditAsyncQuery {

    public static String runMonthlyRollup(Date monthStart) {
        // Async SOQL: query Big Object, write rollup rows to a standard sObject
        String soql =
            'SELECT Order_Id__c, COUNT(Id) totalEvents, MAX(Captured_At__c) lastSeen ' +
            'FROM Order_Audit__b ' +
            'WHERE Captured_At__c >= ' + monthStart.format() + ' ' +
            'GROUP BY Order_Id__c';

        // The result lands in Order_Audit_Rollup__c, one row per Order_Id__c
        Map<String, String> fieldMap = new Map<String, String>{
            'Order_Id__c'         => 'Order_Id__c',
            'totalEvents'         => 'Event_Count__c',
            'lastSeen'            => 'Last_Captured_At__c'
        };

        Database.AsyncQueryResult result = Database.executeAsyncQuery(
            soql,
            'Order_Audit_Rollup__c',
            fieldMap
        );
        return result.AsyncQueryId;
    }

    /** Poll for completion — typically minutes for billions-of-rows queries. */
    public static String getStatus(String asyncQueryId) {
        BackgroundOperation bg = [
            SELECT Status, NumberOfErrors, FinishedDate
            FROM BackgroundOperation
            WHERE Name = :asyncQueryId
            WITH USER_MODE
            LIMIT 1
        ];
        return bg.Status;
    }
}
```

**Rules**:
- **Sync SOQL is for narrow lookups.** A `SELECT ... WHERE` on the leading index field with low cardinality. Anything with aggregation or wide scans must be async
- **Async SOQL writes results, not memory.** Pick a target sObject (custom or standard) with fields matching the projected columns
- **One Async SOQL job at a time per org.** Queueing matters; design the cadence (nightly, hourly) so they don't pile up
- **`BackgroundOperation` is the polling surface.** Status is `Queued | Holding | Running | Complete | Failed | Aborted`. Monitor `NumberOfErrors`
- **Reserve Async SOQL for genuinely big queries.** For ≤50K rows, sync is faster end-to-end

## BIG-4: Querying with Index-Aligned Predicates {#big-index-query}

Standard SOQL on a Big Object only supports a tightly constrained `WHERE` clause: the predicate must be **index-prefix aligned**. You filter on the leading index field with `=` (or `IN`), then optionally narrow on subsequent index fields. No `OR`, no `LIKE`, no functions, no non-indexed fields.

```apex
public class OrderAuditQuery {

    /** Lookup all audit rows for a specific Order — uses the leading index field. */
    public static List<Order_Audit__b> findByOrderId(Id orderId) {
        // Indexed: Order_Id__c (leading), Captured_At__c
        return [
            SELECT Order_Id__c, Captured_At__c, Status__c, Total__c
            FROM Order_Audit__b
            WHERE Order_Id__c = :orderId
            ORDER BY Captured_At__c DESC
            LIMIT 1000
        ];
    }

    /** Time-bounded lookup — leading equality + range on the next index field. */
    public static List<Order_Audit__b> findByOrderIdAndWindow(Id orderId, Datetime since) {
        return [
            SELECT Order_Id__c, Captured_At__c, Status__c, Total__c
            FROM Order_Audit__b
            WHERE Order_Id__c = :orderId
              AND Captured_At__c >= :since
            ORDER BY Captured_At__c DESC
            LIMIT 5000
        ];
    }

    // ❌ Won't work — can't filter on a non-indexed field, even with a leading index field
    // [SELECT ... FROM Order_Audit__b WHERE Order_Id__c = :id AND Status__c = 'Cancelled']
}
```

**Rules**:
- **Leading index field must be `=` or `IN`.** Range predicates only on the *last* indexed field in the prefix you've specified
- **No `OR` across index branches.** Issue two queries and union in memory if needed
- **No filters on non-indexed fields, ever.** If you need them, project them in the SELECT and filter in Apex (or move to Async SOQL into a standard object you can query freely)
- **`LIMIT` is mandatory** for any non-narrow query — sync max is 50,000 rows
- **`ORDER BY`** must reference index fields in the index order. Reverse-order (`DESC` on a `ASC`-indexed field) is allowed; arbitrary ordering is not

## BIG-5: Lifecycle and Capacity Planning {#big-lifecycle}

Big Objects are forever — there's no `delete` API. Plan capacity, retention, and the eventual decommission path before the first write. The decommission path is a destructive change that drops the Big Object entirely.

```apex
// Retention as a write-time decision: tag rows with a TTL bucket
public class Order_Audit_Bucket {

    /** Compute a retention bucket name; older buckets get archived to S3 via the
     *  retention pipeline (BIG-5 is the source signal, not the mover). */
    public static String bucketFor(Datetime captured) {
        return 'YR-' + captured.year() + '-Q' + ((captured.month() - 1) / 3 + 1);
    }
}
```

**Rules**:
- **Capacity is purchased in tiers.** Default 1M rows; commercial tiers go to billions. Track usage via `Database.countQuery` periodically
- **There is no row-level delete.** Don't put data in a Big Object that you'll need to delete for compliance (GDPR right-to-be-forgotten). Use a foreign-key Big Object + a "tombstone" lookup table outside it
- **Decommission = destructive change.** Removing a Big Object means dropping all rows with no recovery. Stage a parallel Big Object → backfill → switch reads → drop
- **Storage is cheaper than standard but not free.** Track per-bucket counts so finance has predictable forecasting
- **Audit-grade access logging.** Profile/permset CRUD is the only access control. For sensitive audit data, log every read via a wrapping Apex class (Big Objects don't have FLS or sharing)

---

## Anti-patterns

- **Putting deletable data in a Big Object.** No row-level delete means GDPR / right-to-be-forgotten requests force a full re-load. Use standard objects with archival jobs instead
- **Designing the index after writing the queries.** The index is permanent and the queries are constrained by it. Reverse the order: list the queries you need, then derive the index fields
- **Filtering on non-indexed fields.** SOQL silently fails or returns 0 rows on certain misuses; always validate the predicate matches the index prefix
- **Using standard `insert` DML.** Compiles but fails at runtime. Always `Database.insertImmediate()` or Bulk API 2.0
- **One catch-all index.** Multiple index fields in one Big Object trying to serve every query — index prefix alignment forces all queries through the leading field. Two narrow Big Objects beat one wide one
- **Treating Async SOQL as a real-time API.** It's analytical — minutes-to-hours latency. Don't wire a UI to wait on it; surface results from the rollup table after the job completes
- **Skipping the destructive-change rehearsal.** A live Big Object holds production data; the first time you exercise the decommission path should NOT be in prod. Rehearse in a sandbox with the same row count tier
