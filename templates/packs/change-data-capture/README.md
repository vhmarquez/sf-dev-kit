# Change Data Capture Pack

Patterns and guidance for **Change Data Capture (CDC)** — Salesforce's auto-emitted change-event stream for record-level diffs across the bus to internal triggers and external subscribers.

## When to use this pack

Install with `/argo:pattern-pack add change-data-capture` if your project:
- Broadcasts record changes to other Salesforce orgs (org-to-org sync)
- Streams changes to external systems (data warehouses, MuleSoft pipelines, lakehouses)
- Has internal subscribers that need cross-record visibility on every change
- Already runs Platform Events and you need a related but distinct surface for raw record changes

Don't install for:
- Pure in-org automation (use Apex triggers / Flows)
- Semantic, business-meaningful events with custom shape (use the `platform-events` pack — PE-1)

## What's in the pack

- **CDC-1: Enabling Change Data Capture for an sObject** — source-controlled `PlatformEventChannel` + `PlatformEventChannelMember` selection
- **CDC-2: Apex Trigger Subscriber for `<Object>ChangeEvent`** — switch on `changeType`, idempotency via `(commitNumber, sequenceNumber)`, GAP handling
- **CDC-3: External Subscriber via Pub/Sub API** — gRPC, replayId as bytes, flow control via `numRequested`
- **CDC-4: GAP_OVERFLOW Handling and Reconciliation** — sweep batch against `LastModifiedDate` when the bus drops events
- **CDC-5: CDC vs. Platform Events Decision** — picking the right surface

Plus checklist additions covering CDC selection, subscriber idempotency, replayId persistence, reconciliation paths, and the CDC-vs-PE decision record.

## What's not in the pack

- Platform Event design — that's the `platform-events` pack (PE-1..5). Many CDC patterns reuse PE building blocks (replay, trigger handler frame); the packs are complementary
- Big-Object archival of change history — see the `big-objects` pack

## Cross-references

- Companion pack: `platform-events` (PE-1..5) — same bus, different schema/trigger model
- Base patterns: SF-7 (Trigger Handler Framework), SF-15 (Named Credentials, for Pub/Sub auth)
- Specialist agents: `@integration-architect` for cross-system designs

## References

- [Change Data Capture Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.change_data_capture.meta/change_data_capture/)
- [Pub/Sub API documentation](https://developer.salesforce.com/docs/platform/pub-sub-api/overview)
- [PlatformEventChannelMember metadata](https://developer.salesforce.com/docs/atlas.en-us.api_meta.meta/api_meta/meta_platformeventchannelmember.htm)
