### Change Data Capture
- [ ] CDC selection is source-controlled via `PlatformEventChannel` + `PlatformEventChannelMember` metadata, not just a Setup-page pick (CDC-1)
- [ ] Subscriber trigger is `after insert` on `<Object>ChangeEvent` and routes through the project's TriggerHandler framework (CDC-2)
- [ ] `switch on changeType` covers every kind: `CREATE`, `UPDATE`, `DELETE`, `UNDELETE`, `GAP_*`
- [ ] Idempotency uses `(commitNumber, sequenceNumber)` — never just record id
- [ ] External subscribers use **Pub/Sub API** (gRPC) for new integrations; CometD reserved for legacy (CDC-3)
- [ ] `replayId` is persisted as bytes (Pub/Sub API) or string (CometD) — never truncated to int
- [ ] A **reconciliation path** exists before the subscriber goes to prod — sweep against `LastModifiedDate` for `GAP_OVERFLOW` (CDC-4)
- [ ] On-call alert wired for `GAP_OVERFLOW` events
- [ ] Decision recorded (in an ADR or design doc) for "why CDC vs. Platform Event" when both could fit (CDC-5)
