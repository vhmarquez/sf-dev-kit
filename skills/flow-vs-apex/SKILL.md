---
name: flow-vs-apex
description: Decide whether a new piece of automation should be built as a Flow, an Apex Trigger, or another mechanism. Asks the user 6–8 quick questions, then recommends with rationale. No code generated.
---

You are helping the user choose between **Flow**, **Apex Trigger**, **Apex Queueable/Batch**, **Platform Event**, or **External Service** for a new piece of automation. Ask the questions below in order, take their answers, then recommend with a one-paragraph rationale.

## Read Project Config First (optional context)

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
```

If the org cache exists, peek at active Flows on the affected object so the recommendation can reference existing automation.

## Input

`$ARGUMENTS`:
- (empty) — interactive Q&A
- `<one-line description>` — interactive Q&A seeded with the description for context
- `--object <Object>` — pre-fill the affected object so the questions are concrete
- `--non-interactive answers="..."` — accept answers as a comma-separated list (for scripted use)

## Decision questions

Ask in order. Skip questions that are obviously answered by the description.

1. **What's the input?** record-triggered (insert/update/delete), scheduled, user-initiated (button/screen), platform event, callout from external?
2. **What's the volume?** under 200 records per call, 200–10K per batch, > 10K?
3. **What's the operation?** field set / record creation / cross-object update / external callout / async work / delete cleanup?
4. **Who owns it after build?** the dev team (in source) or the admin team (declarative)?
5. **Does it need transaction control?** rollback on partial failure, savepoints?
6. **Does it need callouts?** outbound HTTP, MuleSoft, external systems?
7. **Are there sharing/security implications?** must respect record-level sharing? Or run as system?
8. **Existing automation on the object?** (Check `/sf-dev-kit:flow-audit <Object>` if available)

## Decision tree

```
record-triggered AND volume <= 200 AND simple field updates AND admin-owned
  → Flow (record-triggered, before-save if same-record, after-save otherwise)

record-triggered AND volume > 200 OR complex logic OR transaction control
  → Apex Trigger + TriggerHandler framework (SF-7)

scheduled AND volume <= 100 records of work
  → Schedulable Apex calling Queueable

scheduled AND volume > 100 records OR runtime > 10s
  → Database.Batchable (Batch Apex)

user-initiated screen AND admin-owned AND single-record
  → Screen Flow

user-initiated screen AND complex multi-step OR custom UI
  → LWC + Apex controller (SF-6 AuraEnabled)

external event in
  → Platform Event subscriber (Apex trigger on the __e channel) — see `pattern-pack add platform-events`

callout out, transactional
  → Apex with Named Credential (SF-15)

callout out, fire-and-forget after commit
  → Queueable with callout, with static guard (PRJ-6) — or Platform Event publish + external subscriber
```

## Output

```
# Automation Choice: <one-line description>

## Answers
- Input:               record-triggered (after-update on Order__c)
- Volume:              up to 5,000 records per batch import
- Operation:           cross-object update + outbound notification
- Owner:               dev team
- Transaction control: rollback on failure required
- Callouts:            yes — to Order Management API
- Sharing:             must respect user sharing (caller is internal user)
- Existing automation: 1 active Flow on Order__c (`Order_Set_Region_AfterSave`)

## Recommendation: **Apex Trigger + Queueable for callout**

### Why
- Volume of 5K records exceeds Flow's reliable threshold (Flow is fine up to ~200, brittle above)
- Transaction control rules out Flow (no native rollback; partial-record DML)
- Callout in transaction would block the trigger; Queueable defers it, respects governor limits, and chains cleanly
- Coexisting Flow on the same object (`Order_Set_Region_AfterSave`) is fine — Flow runs first (before-save Flows always do; after-save run before triggers in the order documented [here](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_triggers_order_of_execution.htm))

### Implementation outline (for @architect / @apex-dev)
- Trigger: `OrderTrigger` (after update) → `TriggerDispatcher.Run(new OrderTriggerHandler())`
- Handler: collect changed records, push to `OrderNotifyQueueable` (with PRJ-6 static guard)
- Queueable: callout via Named Credential `Order_API` (SF-15), retry policy on transient failure (PE-5 if you ever migrate to Platform Event)

### Patterns referenced
- SF-7 (Trigger Handler Framework)
- SF-15 (HTTP Callout via Named Credential)
- PRJ-6 (Queueable with Static Guard)

### Alternatives considered
- **Pure Flow**: would have to subdivide work into chunks under 200; transaction-control limits make this brittle for the 5K case
- **Platform Event**: viable if you control both publisher and consumer and want decoupling; overkill for a single project-internal notification
- **Outbound Message**: legacy; not recommended for new work
```

## Exit codes
- 0 — recommendation produced
- 2 — input parsing error

## Rules

- **Don't generate code.** This skill recommends; `@architect` / `@apex-dev` implement
- **Always cite existing automation** if the org cache shows it. Coexisting Flow + Apex is fine but the dev needs to know
- **Be opinionated.** "It depends" is unhelpful — pick one and explain
- **Show alternatives.** The user may know something you don't; surface 1–2 alternatives so they can push back
