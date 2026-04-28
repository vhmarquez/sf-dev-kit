## PE-1: Platform Event Publisher (Apex) {#pe-publisher}

Publish a Platform Event from Apex. Use `publish-after-commit` semantics by default — the event fires only if the surrounding transaction commits, so events match the persisted record state.

```apex
public with sharing class OrderEventPublisher {

    public static void publishOrderCreated(Order__c o) {
        if (o == null || o.Id == null) {
            throw new IllegalArgumentException('Order must be persisted before publishing');
        }

        Order_Created__e evt = new Order_Created__e(
            Order_Id__c = o.Id,
            Customer_Id__c = o.Customer__c,
            Total__c = o.Total_Amount__c,
            Occurred_At__c = Datetime.now()
        );

        // publish-after-commit semantics: built-in for standard-volume PE since Spring '21
        Database.SaveResult sr = EventBus.publish(evt);
        if (!sr.isSuccess()) {
            for (Database.Error err : sr.getErrors()) {
                Logger.log('OrderEventPublisher: ' + err.getStatusCode() + ' ' + err.getMessage());
            }
            throw new EventBus.EventPublishException('Failed to publish Order_Created__e');
        }
    }
}
```

**Rules**:
- Don't publish from a `before` trigger — the record may not commit. Publish from `after` triggers or service classes called after persistence
- Standard-volume PE has publish-after-commit by default; high-volume PE (PE-4) requires opt-in via `EventBus.PublishAfterCommitMessage` interface
- Don't include sensitive data in event fields — events are visible to all subscribers in the org
- Publishing counts toward DML governor limit
- Test with `Test.getEventBus().deliver()` after publishing in a `Test.startTest`/`Test.stopTest` block

## PE-2: Apex Trigger Subscriber for Platform Events {#pe-trigger-subscriber}

Subscribe with a trigger on the platform event sObject. The trigger receives a batch of events; handle them through the project's TriggerHandler framework so they get tested and instrumented like any other trigger.

```apex
trigger Order_CreatedTrigger on Order_Created__e (after insert) {
    TriggerDispatcher.Run(new Order_CreatedTriggerHandler());
}
```

```apex
public class Order_CreatedTriggerHandler implements ITriggerHandler {

    public void afterInsert() {
        Map<Id, Order__c> ordersToUpdate = new Map<Id, Order__c>();

        for (Order_Created__e evt : (List<Order_Created__e>) Trigger.new) {
            // EventBus.TriggerContext gives us replay/retry semantics
            if (String.isBlank(evt.Order_Id__c)) {
                continue;
            }

            ordersToUpdate.put(evt.Order_Id__c, new Order__c(
                Id = evt.Order_Id__c,
                Status__c = 'Acknowledged'
            ));
        }

        if (!ordersToUpdate.isEmpty()) {
            try {
                update as user ordersToUpdate.values();
            } catch (Exception e) {
                Logger.log('Order_CreatedTriggerHandler: ' + e);
                EventBus.TriggerContext.currentContext().setResumeCheckpoint(
                    Trigger.new[Trigger.new.size() - 1].ReplayId
                );
                throw e;  // forces retry of subsequent events
            }
        }
    }

    // other ITriggerHandler stubs (beforeInsert/etc.) return without action
}
```

**Rules**:
- Subscribers run as the **Automated Process** user, not as the publishing user. `with sharing` and `as user` won't reflect the publisher's identity
- Idempotency is the subscriber's job. Always be safe under "this event was delivered twice"
- Use `EventBus.TriggerContext.currentContext().setResumeCheckpoint(replayId)` to retry subsequent events from a known-good point on partial failure
- Subscribers count toward async governor limits, not sync — they have 200 SOQL / etc.
- One subscriber trigger per event sObject; route work to handler classes from there

## PE-3: Platform Event Replay {#pe-replay}

LWC subscribers (via `lightning/empApi`) and external subscribers receive a `replayId` per event. Persist the highest-seen `replayId` per channel; on reconnect, request `-1` (all new events) or the last-seen replayId+1 for catch-up.

```javascript
import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

export default class OrderEventListener extends LightningElement {
    channelName = '/event/Order_Created__e';
    subscription = null;
    lastReplayId = -1; // -1 means "new events only"

    connectedCallback() {
        const replayId = parseInt(localStorage.getItem(this.channelName), 10);
        if (Number.isFinite(replayId)) {
            this.lastReplayId = replayId;
        }
        this.handleSubscribe();
    }

    handleSubscribe() {
        subscribe(this.channelName, this.lastReplayId, (response) => {
            const evt = response.data?.payload;
            const meta = response.data?.event;
            if (!evt) return;

            // Idempotent: skip if we've already handled this replayId
            if (meta.replayId <= this.lastReplayId) return;

            this.processEvent(evt);
            this.lastReplayId = meta.replayId;
            localStorage.setItem(this.channelName, this.lastReplayId);
        }).then(s => { this.subscription = s; });
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
        }
    }

    processEvent(evt) {
        // domain logic here
    }
}
```

**Rules**:
- ReplayId is monotonic per channel; persist the *latest seen*, not the latest received
- Replay window: standard-volume PE = 24 hours; high-volume = 72 hours
- On reconnect, ask for `lastReplayId + 1` to resume; on first connect, use `-1`
- LocalStorage is fine for single-tab use cases; for multi-tab durability use Apex-stored state per user
- Don't store payloads in localStorage — only the replayId

## PE-4: High-Volume Platform Events {#pe-high-volume}

For >250K events/hour or where 24h replay isn't enough. Marked at definition time as "High Volume". Different governor profile, different replay window (72h), different publish semantics.

```apex
public class HighVolumeOrderPublisher {
    public static void publish(List<Order__c> orders) {
        List<Order_Stream__e> events = new List<Order_Stream__e>();
        for (Order__c o : orders) {
            events.add(new Order_Stream__e(
                Order_Id__c = o.Id,
                Customer_Id__c = o.Customer__c,
                // partition key controls parallelism on the bus side
                ReplayId__c = null  // server-assigned
            ));
        }

        // High-volume PE requires explicit publish-after-commit if needed:
        // EventBus.publish(events, EventBus.PublishAfterCommitMessage)
        List<Database.SaveResult> results = EventBus.publish(events);
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                Logger.log('HighVolumeOrderPublisher: ' + sr.getErrors());
            }
        }
    }
}
```

**Rules**:
- Use a **partition key field** (custom field) to control event-bus parallelism — events with the same key are ordered, different keys can be processed in parallel
- Don't subscribe with multiple Apex triggers to the same high-volume channel — concurrency model is per-channel, not per-trigger
- Test with `Test.getEventBus().deliver()` — same as standard-volume
- Publish-after-commit is **opt-in** for high-volume; without it, events fire immediately on `EventBus.publish` regardless of transaction outcome

## PE-5: Platform Event Error Handling {#pe-error-handling}

Event subscribers can fail. Salesforce retries automatically up to 9 times for high-volume PE; standard-volume retries on the same trigger context once. Use `setResumeCheckpoint` and `setRetry` to control replay.

```apex
public class Order_CreatedTriggerHandler implements ITriggerHandler {
    public void afterInsert() {
        EventBus.TriggerContext ctx = EventBus.TriggerContext.currentContext();

        for (Integer i = 0; i < Trigger.new.size(); i++) {
            Order_Created__e evt = (Order_Created__e) Trigger.new[i];
            try {
                process(evt);
            } catch (TransientException e) {
                // Set checkpoint to this replay so retry resumes from here
                ctx.setResumeCheckpoint(evt.ReplayId);
                throw e;
            } catch (Exception e) {
                // Permanent error — log and skip; don't block the rest of the batch
                Logger.log('Permanent error on event ' + evt.ReplayId + ': ' + e);
            }
        }
    }
}
```

**Rules**:
- Distinguish **transient** (network, lock, governor) from **permanent** (bad data) errors. Retry transient, skip-and-log permanent
- `ctx.setResumeCheckpoint(replayId)` tells Salesforce to retry from that point. Without it, retry is at the batch boundary
- 9 retries max for high-volume; afterward the event is in `EventDeliveryStatus = 'Disabled'` and emits a `BatchApexErrorEvent`
- Subscribe to `BatchApexErrorEvent` separately for dead-letter handling

---

## Anti-patterns

- **Publishing from a `before` trigger.** Records aren't committed yet; if the transaction rolls back, you've published a phantom event. Use `after` triggers or service-layer publishes
- **Storing PII in event fields.** Events are visible to every subscriber in the org. Pass `Id`s and let subscribers `WITH USER_MODE` read from the source object
- **Subscribing with multiple triggers on the same high-volume channel.** Salesforce's parallelism model assumes a single trigger per channel; multiple triggers race
- **Treating Platform Events like a queue.** They're at-least-once delivery, not exactly-once. Subscribers must be idempotent — design for replay
- **Forgetting publish-after-commit on high-volume PE.** Default for high-volume is fire-immediately; tx rollback won't suppress the event
