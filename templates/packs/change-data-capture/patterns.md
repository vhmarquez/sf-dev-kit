_TODO: Authoring stub. See `README.md` for the intended pattern list._

## CDC-1: Enabling Change Data Capture for an sObject {#cdc-enable}

_TODO_: Steps for the Setup → Change Data Capture page; metadata XML option (`PlatformEventChannel` + `PlatformEventChannelMember`); deployable definition shape.

## CDC-2: Apex Trigger Subscriber for `<Object>ChangeEvent` {#cdc-trigger-subscriber}

_TODO_: Trigger on `<Object>ChangeEvent` channel; handle `ChangeEventHeader.changeType` switch (CREATE / UPDATE / DELETE / UNDELETE / GAP_OVERFLOW); replay-id propagation from header; idempotency via `recordIds` + `commitNumber` dedup.

## CDC-3: External Subscriber via Pub/Sub API {#cdc-external-subscriber}

_TODO_: gRPC-based Pub/Sub API; replay-id semantics; CometD vs Pub/Sub API tradeoffs; sample subscriber pseudo-code.

## CDC-4: GAP_OVERFLOW Handling {#cdc-gap-overflow}

_TODO_: When the change bus drops events (>3-day replay window or backpressure); recovery via Bulk API record-level diff against last known state.

## CDC-5: CDC vs Platform Events Decision {#cdc-vs-pe}

_TODO_: Decision matrix — auto-emitted vs explicit publish; fixed shape vs custom; 3-day vs 24h replay; in-org vs cross-org; intra-Salesforce vs external.

---

## Anti-patterns

_TODO_: Common mistakes (treating CDC as a transactional sync; ignoring `GAP_OVERFLOW`; subscribing to too many channels at once and exhausting Pub/Sub API quota).
