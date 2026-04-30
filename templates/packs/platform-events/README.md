# Platform Events Pack

Patterns and guidance for **Salesforce Platform Events** (PE) — Salesforce's built-in pub/sub event bus, suited for cross-system broadcasts and decoupled async workflows.

## When to use this pack

Install with `/argo:pattern-pack add platform-events` if your project:
- Publishes events from Apex / Flow that other systems consume
- Subscribes to external pub/sub events surfaced via Platform Events
- Needs decoupled async patterns where Queueable would tightly couple producer and consumer
- Coordinates state across multiple Salesforce orgs

## What's in the pack

- **PE-1: Platform Event Publisher (Apex)** — `EventBus.publish` with publish-after-commit semantics
- **PE-2: Apex Trigger Subscriber** — handler-class style, replay-id-aware
- **PE-3: Platform Event Replay** — using EmpApi (LWC) and `@channelName('/event/X__e')` (Apex) with stored ReplayId
- **PE-4: High-Volume Platform Events** — partition keys, 1M+ events/24h tier
- **PE-5: Platform Event Error Handling** — `EventBus.TriggerContext.currentContext()` retry semantics

Plus checklist additions for Apex/Async covering replay-id persistence, idempotent subscribers, and standard-vs-high-volume choice.

## What's not in the pack

- Change Data Capture (different event flavor — see the `change-data-capture` pack)
- Outbound messages (legacy)
- streaming-API style PushTopics (legacy; CDC superseded these)

## Worked example

`examples/order-events.zip` (placeholder — extract for a 2-class + 1-LWC reference implementation of order-status broadcast).

## References

- [Platform Events Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/)
- [Replay-id semantics](https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/platform_events_subscribe_apex.htm)
