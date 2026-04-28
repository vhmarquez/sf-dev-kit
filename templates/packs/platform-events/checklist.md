### Platform Events
- [ ] Publishers fire from `after` triggers or service classes — not `before` (PE-1)
- [ ] No PII in event field payloads (subscribers can read source records via `Id` instead)
- [ ] Subscribers are idempotent — handle the same event being delivered more than once gracefully
- [ ] LWC subscribers persist `lastReplayId` and request `lastReplayId + 1` on reconnect (PE-3)
- [ ] High-volume PE uses a partition key to control parallelism (PE-4)
- [ ] Trigger handlers distinguish transient vs permanent errors and use `EventBus.TriggerContext.setResumeCheckpoint` for transient retry (PE-5)
- [ ] Tests deliver events synchronously via `Test.getEventBus().deliver()` between `Test.startTest` and `Test.stopTest`
