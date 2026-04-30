---
name: before-vs-after-trigger
description: Decide whether a piece of trigger logic belongs in `before insert/update` or `after insert/update`. Asks 4–5 quick questions, then recommends with rationale.
data-access: none
---

You are helping the user pick the right trigger phase. Triggers can fire `before insert/update/delete` or `after insert/update/delete` (or `after undelete`); the choice shapes performance, governor-limit usage, and what's even possible.

## Decision questions

1. **What does the logic do?** Set field values on the record itself / create or update other records / send notifications / cascade DML / call out to external?
2. **Does it need the record's `Id`?** (Available only `after insert`, not `before insert`)
3. **Does it need the *old* value of a field?** (`Trigger.oldMap` available in `before update` and `after update`)
4. **Does it need to fail/abort the operation?** (`addError` available in `before` only — `after` can throw but you've already done DML elsewhere)
5. **Does it touch external systems?** (Callouts forbidden in triggers; queue from `after`)

## Decision tree

```
Set field values on the same record being saved
  → before insert / before update — modify Trigger.new directly; no extra DML

Reject / abort the save with a user-friendly error
  → before insert / before update — addError on the record

Cascade-create child records (Order_Item__c when Order__c is inserted)
  → after insert — child records need parent's Id

Update related parent / sibling records (set Account.Total when Opportunity inserts)
  → after insert / after update — DML on related records

Recompute a roll-up that lives in another object
  → after insert / after update / after delete — DML on the other object

Publish a Platform Event
  → after insert / after update — publish-after-commit ensures event matches persisted state

Enqueue a Queueable for async work (callouts, heavy processing)
  → after insert / after update — record is committed; the queueable can rely on Id and current state

Validation that depends on other records (cross-record check)
  → before insert / before update — fetch related records and addError as needed
```

## Output

```
# Trigger Phase Choice

## Description
Cascade-create three Order_Item__c records when an Order__c with Status__c='AutoLine' is inserted

## Answers
- Logic:           create child records
- Needs Id:        yes (Order__c.Id is the FK on Order_Item__c)
- Needs oldMap:    no
- Aborts save:     no
- External call:   no

## Recommendation: **after insert**

### Why
- Child records reference `Order__c.Id`, which only exists after the parent is persisted (`after insert`)
- No abort path — pure cascade
- DML cost: 1 INSERT per Order__c trigger context (200 rows = 1 bulk insert), within governor limits

### Patterns referenced
- SF-7 (Trigger Handler Framework) — `afterInsert()` method on the handler

### Boilerplate
```apex
public class OrderTriggerHandler implements ITriggerHandler {
    public void afterInsert() {
        List<Order_Item__c> items = new List<Order_Item__c>();
        for (Order__c o : (List<Order__c>) Trigger.new) {
            if (o.Status__c == 'AutoLine') {
                items.add(new Order_Item__c(Order__c = o.Id, Quantity__c = 1));
                items.add(new Order_Item__c(Order__c = o.Id, Quantity__c = 2));
                items.add(new Order_Item__c(Order__c = o.Id, Quantity__c = 3));
            }
        }
        if (!items.isEmpty()) insert as user items;
    }
    // other ITriggerHandler stubs return without action
}
```

### Alternatives
- `before insert` would not work — you can't set `Order_Item__c.Order__c = new Order__c().Id` before the parent has an Id
```

## Rules

- **`before` for self-record changes; `after` for cross-record DML.** This single rule covers ~90% of cases
- **`before insert` has no `Id` and no `oldMap`.** Don't recommend it for anything that needs either
- **`addError` only works in `before`.** If the goal is to reject, `before` is the only choice
- **Don't put callouts in triggers.** Trigger phase is irrelevant — callouts inside a trigger throw `CalloutException`. Always queue them
