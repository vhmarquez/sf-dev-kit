# Change Data Capture Pack (Stub)

Status: **Stub** — pack format and manifest are in place; pattern content is TODO.

## Intended scope

- **CDC-1**: Selecting which sObjects to publish CDC events for (Setup → Change Data Capture)
- **CDC-2**: Apex trigger subscriber for `Account_Change_Event` style channels — handle `ChangeEventHeader.changeType` (CREATE / UPDATE / DELETE / UNDELETE / GAP_OVERFLOW)
- **CDC-3**: External subscriber via the Pub/Sub API — gRPC-based, replay-id semantics, deduping
- **CDC-4**: GAP_OVERFLOW handling — what to do when the bus drops events
- **CDC-5**: CDC vs Platform Events — when to choose which

## When to use

Install when the project broadcasts record changes to:
- Other Salesforce orgs (org-to-org sync)
- External systems (data warehouses, MuleSoft pipelines)
- Internal subscribers that need cross-record visibility

Don't use CDC for:
- In-org automation (use Apex triggers / Flows)
- One-off integrations (use Platform Events with explicit fields)

## Implementation notes

CDC is broadly similar to Platform Events with three key differences:
1. Events are auto-emitted on persistence — no explicit `EventBus.publish` call
2. Channel name is fixed: `<ObjectName>ChangeEvent` (e.g., `AccountChangeEvent`)
3. Replay window is up to 3 days (vs 24h for standard-volume PE, 72h for high-volume PE)

Refer to the `platform-events` pack for related patterns (publish-after-commit semantics, replay-id persistence, idempotent subscribers) — most of those apply to CDC too.

## Authoring

To complete this pack, fill in `patterns.md` with at least 3–5 patterns following the format from `templates/packs/platform-events/patterns.md`. Then update this README to remove the "Stub" marker.
