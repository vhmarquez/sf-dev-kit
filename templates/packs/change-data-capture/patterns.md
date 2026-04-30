## CDC-1: Enabling Change Data Capture for an sObject {#cdc-enable}

CDC emits change events for selected sObjects to the `/data/<Object>ChangeEvent` channel. Two ways to enable: declarative (Setup → Change Data Capture, picks survive in source via retrieved `PlatformEventChannel` + `PlatformEventChannelMember` metadata) or fully source-controlled (author the metadata directly).

```xml
<!-- force-app/main/default/platformEventChannels/ChangeEvents.platformEventChannel-meta.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<PlatformEventChannel xmlns="http://soap.sforce.com/2006/04/metadata">
    <channelType>data</channelType>
    <label>Change Events</label>
</PlatformEventChannel>
```

```xml
<!-- force-app/main/default/platformEventChannelMembers/ChangeEvents_OrderChangeEvent.platformEventChannelMember-meta.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<PlatformEventChannelMember xmlns="http://soap.sforce.com/2006/04/metadata">
    <eventChannel>ChangeEvents</eventChannel>
    <selectedEntity>OrderChangeEvent</selectedEntity>
</PlatformEventChannelMember>
```

For a custom object: `selectedEntity` is `<Object>__ChangeEvent` (e.g., `Order__ChangeEvent`).

**Rules**:
- **Source-control your CDC selection.** Setup-page picks are easy to lose during sandbox refresh. Always retrieve `PlatformEventChannel` + `PlatformEventChannelMember` into source
- **CDC is opt-in per object.** Selecting one custom object doesn't enable its parents or children
- **Field-level changes are captured by default**, including formula fields recomputed by the change. If you only need header-level signals (create/update/delete), filter inside the subscriber rather than disabling field tracking
- **Standard objects vary.** Some standard objects (e.g., Quote) need an extra entitlement; check the org's CDC entitlements before assuming it'll deploy
- **One channel per integration domain.** Don't put 30 sObject members on one channel "to keep things simple" — the subscriber receives all of them and has to filter

## CDC-2: Apex Trigger Subscriber for `<Object>ChangeEvent` {#cdc-trigger-subscriber}

Subscribe with an `after insert` trigger on the `<Object>ChangeEvent` sObject. The trigger receives a batch of change events; route through the project's TriggerHandler framework. The `ChangeEventHeader` field carries the change kind, recordIds, and replay metadata.

```apex
trigger OrderChangeEventTrigger on OrderChangeEvent (after insert) {
    TriggerDispatcher.Run(new OrderChangeEventTriggerHandler());
}
```

```apex
public class OrderChangeEventTriggerHandler implements ITriggerHandler {

    public void afterInsert() {
        Set<Id> created = new Set<Id>();
        Set<Id> updated = new Set<Id>();
        Set<Id> deleted = new Set<Id>();

        for (OrderChangeEvent ce : (List<OrderChangeEvent>) Trigger.new) {
            EventBus.ChangeEventHeader hdr = ce.ChangeEventHeader;
            // Idempotency: dedup against (commitNumber, sequenceNumber, recordIds)
            if (Order_CDC_Dedup.alreadySeen(hdr.commitNumber, hdr.sequenceNumber)) {
                continue;
            }

            switch on hdr.changeType {
                when 'CREATE'   { created.addAll(hdr.recordIds); }
                when 'UPDATE'   { updated.addAll(hdr.recordIds); }
                when 'DELETE'   { deleted.addAll(hdr.recordIds); }
                when 'UNDELETE' { created.addAll(hdr.recordIds); }
                when 'GAP_OVERFLOW' {
                    // See CDC-4 — fall back to a reconciliation sweep
                    Order_CDC_Reconciler.scheduleSweep(hdr.recordIds);
                    continue;
                }
                when 'GAP_CREATE', 'GAP_UPDATE', 'GAP_DELETE', 'GAP_UNDELETE' {
                    // Gap events: change happened but field-level diff is unavailable
                    Order_CDC_Reconciler.scheduleRecord(hdr.recordIds[0]);
                    continue;
                }
            }

            Order_CDC_Dedup.mark(hdr.commitNumber, hdr.sequenceNumber);
        }

        // Process the buckets — each method is bulk-safe
        if (!created.isEmpty()) Order_Sync.onCreated(created);
        if (!updated.isEmpty()) Order_Sync.onUpdated(updated);
        if (!deleted.isEmpty()) Order_Sync.onDeleted(deleted);
    }

    // other ITriggerHandler stubs return without action
}
```

**Rules**:
- **Always handle every `changeType`.** `CREATE`, `UPDATE`, `DELETE`, `UNDELETE`, plus the `GAP_*` family. Missing one means silently dropping events
- **`recordIds` is plural.** A single change event may aggregate multiple records when changes share a commit and sequence — iterate the list
- **Idempotency via `(commitNumber, sequenceNumber)`** — that pair is unique per change. Persist the highest seen and dedup retried events
- **Subscribers run as the Automated Process user.** `with sharing` reflects that user; not the user who made the change
- **Use the `as user` DML mode** when writing into other objects to inherit the running user's CRUD/FLS — even if the running user is Automated Process, this surfaces gaps explicitly
- **Async governor profile applies.** 200 SOQL / 150 DML — but events arrive in batches up to 2,000

## CDC-3: External Subscriber via Pub/Sub API {#cdc-external-subscriber}

External systems (Node, Python, Java) subscribe over the gRPC-based **Pub/Sub API**. CometD is legacy; new integrations use Pub/Sub for higher throughput and back-pressure semantics. Authenticate with a Connected App + JWT bearer flow, subscribe to the topic `/data/<Object>ChangeEvent`, then process binary Avro payloads.

```javascript
// node — using @salesforce/pubsub-api-node-client
import { PubSubApiClient } from 'salesforce-pubsub-api-client';

const client = new PubSubApiClient({
    authType: 'oauth-jwt',
    loginUrl: process.env.SF_LOGIN_URL,
    clientId: process.env.SF_CLIENT_ID,
    username: process.env.SF_USERNAME,
    privateKey: process.env.SF_JWT_PRIVATE_KEY,
});

await client.connect();

const lastReplay = await store.get('order-cdc-replay');  // Buffer | null

await client.subscribe(
    '/data/OrderChangeEvent',
    /* numRequested */ 100,
    async (subscription, callbackType, data) => {
        if (callbackType !== 'event') return;
        const evt = data.payload;
        const hdr = evt.ChangeEventHeader;

        // Idempotency: skip if we've processed this commit+seq
        if (await store.seen(hdr.commitNumber, hdr.sequenceNumber)) return;

        try {
            await process(evt);
            await store.mark(hdr.commitNumber, hdr.sequenceNumber);
            await store.set('order-cdc-replay', data.replayId);  // monotonic
        } catch (err) {
            // Don't ack — the next subscribe call will resend from replayId
            throw err;
        }
    },
    /* replayPreset */ lastReplay ? 'CUSTOM' : 'LATEST',
    /* replayId */    lastReplay
);
```

**Rules**:
- **Use Pub/Sub API for new integrations.** CometD is supported but deprecated for high-volume; Pub/Sub provides flow control via `numRequested`
- **`replayId` is opaque bytes** in Pub/Sub API (vs. integer in CometD). Persist as a `Buffer`/byte-array, not a number
- **Replay window is 3 days** for CDC. A subscriber down longer than that misses events — catch up via Bulk API diff (CDC-4)
- **Pub/Sub flow control matters.** Don't request more events than your processor can handle; back-pressure manifests as `unprocessedEventCount` rising
- **Ack only on success.** Persist replayId after `process()` returns; if the process crashes mid-handler, the next connection re-receives from the last good replayId
- **Avro schemas evolve.** Cache the schema from the bus; don't hard-code. New CDC fields can land mid-deploy

## CDC-4: GAP_OVERFLOW Handling and Reconciliation {#cdc-gap-overflow}

The change bus drops events when the replay window expires (>3 days), or under sustained back-pressure. Subscribers see `GAP_OVERFLOW` (entire window dropped) or `GAP_CREATE` / `GAP_UPDATE` / `GAP_DELETE` (one record's field-level diff is unavailable). Recovery is a record-level diff against the source object using Bulk API or SOQL with `LastModifiedDate`.

```apex
public class Order_CDC_Reconciler {

    /** Sweep all records modified since the last known-good replay timestamp. */
    public static void sweepSince(Datetime lastGoodCheckpoint) {
        Database.executeBatch(new Order_CDC_ReconcileBatch(lastGoodCheckpoint));
    }

    /** One-record fallback when a GAP_<changeType> arrives. */
    public static void scheduleRecord(Id recordId) {
        System.enqueueJob(new Order_CDC_ReconcileSingle(recordId));
    }

    /** Hard reset after GAP_OVERFLOW — sweep the whole tenant. */
    public static void scheduleSweep(List<Id> hintRecordIds) {
        Order_Sync_Audit__c row = new Order_Sync_Audit__c(
            Reason__c = 'GAP_OVERFLOW',
            Hint_Record_Count__c = hintRecordIds.size(),
            Triggered_At__c = Datetime.now()
        );
        insert as user row;
        sweepSince(Datetime.now().addHours(-72));  // CDC retention is 3 days
    }
}

public class Order_CDC_ReconcileBatch implements Database.Batchable<sObject> {
    private Datetime since;
    public Order_CDC_ReconcileBatch(Datetime since) { this.since = since; }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Status__c, Customer__c, Total_Amount__c, LastModifiedDate
            FROM Order__c
            WHERE LastModifiedDate >= :since
            WITH USER_MODE
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Order__c> scope) {
        // Compare against the downstream system's last-seen state and emit deltas
        Order_Sync.reconcile(scope);
    }

    public void finish(Database.BatchableContext bc) { /* notify */ }
}
```

**Rules**:
- **Treat `GAP_OVERFLOW` as a critical signal.** Page on it; it means the subscriber fell off the bus. Sweep the full retention window (72h) by default
- **`GAP_<changeType>` is per-record.** The header tells you a change happened, but `changedFields` is empty. Re-fetch the record and recompute downstream state
- **Always have a reconciliation path.** A subscriber that only handles `CREATE`/`UPDATE`/`DELETE` is one outage away from data divergence. Build the sweep before you need it
- **Reconciliation is idempotent by nature.** It compares state, so safe to re-run; that property makes it the safety net for any subscriber bug
- **Track reconciliation runs.** Log to an `Integration_Audit__c` object so on-call can correlate "downstream looks weird" with "reconciler ran 4h ago"

## CDC-5: CDC vs. Platform Events Decision {#cdc-vs-pe}

Both ride the event bus, both have replayId, both subscribe via Apex triggers or Pub/Sub. They diverge on **who decides the schema**, **who triggers the publish**, **what lives on the wire**, and **how long the replay window is**. Pick CDC for record-change broadcast, Platform Events for explicit, custom-shape signals.

| Concern | CDC | Platform Events |
|---------|-----|-----------------|
| Schema | Salesforce-defined `<Object>ChangeEvent`, includes `ChangeEventHeader` + `changedFields` | You define a custom `__e` sObject with chosen fields |
| Trigger | Auto-emitted on every record change to enabled sObjects | Explicit `EventBus.publish()` call |
| Granularity | Field-level diff (which fields changed) | Whatever you put in the payload |
| Replay window | 3 days | 24h (standard) / 72h (high-volume) |
| Volume controls | Per-org daily delivery cap; channel-level concurrency | Standard vs high-volume; high-volume opts into different governor + partition keys |
| Multi-org | Yes — same channel works cross-org via Pub/Sub | Yes |
| Use when | "Tell me when an Order changes" | "Tell me when an Order ships" (semantic event) |
| Don't use when | You only care about a domain event, not raw record changes | You need every field change without designing a payload |

**Decision shortcuts**:
- **Need every record change** → CDC
- **Need semantic, business-meaningful events with custom shape** → Platform Event (PE-1)
- **Need both** (semantic publish AND change broadcast) → publish PE from a CDC trigger handler when domain conditions are met. Don't double-publish from the source trigger
- **External system needs read-only sync** → CDC + Pub/Sub API (CDC-3)
- **External system needs a transactional handshake** → REST or Apex Trigger publishing PE; CDC is fire-and-forget

---

## Anti-patterns

- **Treating CDC as a transactional sync.** It's at-least-once with a 3-day replay window — a transactional sync needs explicit acks and is better served by Apex REST (SF-16) or Pub/Sub-with-server-managed-position
- **Ignoring `GAP_OVERFLOW`.** Subscribers that only handle `CREATE`/`UPDATE`/`DELETE` silently drift after any outage. Always have a reconciliation path (CDC-4)
- **Selecting too many sObjects on one channel.** A channel with 20 entities serves all of them to the subscriber, even if it only cares about 2. Split into per-domain channels
- **Hard-coding the Avro schema.** Salesforce evolves CDC schemas (new fields appear); subscribers must fetch the schema from the bus per connection
- **Subscribing from `before insert` on `<Object>ChangeEvent`.** Only `after insert` is supported on change events. The platform won't deploy a `before` trigger but new authors hit this
- **Persisting only the integer ReplayId.** In Pub/Sub API, replayId is opaque bytes; storing as int truncates and silently breaks resume after the first big jump
- **Using CDC to detect agent-driven changes.** Agents run as users; their changes flow through CDC like any other. If you need to distinguish "agent changed this" from "human changed this", check `ChangeEventHeader.changeOrigin` instead of inferring from the user
