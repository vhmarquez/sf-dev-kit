## FS-1: Work Order Lifecycle Modeling {#fs-work-order-lifecycle}

The core Field Service object graph is **Work Order → Work Order Line Item → Service Appointment → Assigned Resource**. Status changes ripple across these objects through Status Transitions metadata; don't replicate that logic in Apex.

```xml
<!-- force-app/main/default/workOrderStatuses/Scheduled.workOrderStatus-meta.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<WorkOrderStatus xmlns="http://soap.sforce.com/2006/04/metadata">
    <category>InProgress</category>
    <label>Scheduled</label>
    <isDefault>false</isDefault>
    <transitionTo>
        <label>Dispatched</label>
        <restrictTransition>true</restrictTransition>
    </transitionTo>
    <transitionTo>
        <label>Cancelled</label>
    </transitionTo>
</WorkOrderStatus>
```

The status category (`New`, `InProgress`, `Completed`, `Cannot Complete`, `Closed`) drives reporting and SLA semantics. Apex automation should read `Status.Category`, not the per-org status label.

**Rules**:
- **Status category, not label, drives logic.** Customers rename status labels; the category is stable
- **Use Status Transitions metadata for valid moves.** Don't enforce in Apex — the platform already does and the customer can configure it
- **Don't auto-transition from `Closed`.** Once a Work Order or Service Appointment is `Closed`, treat it as immutable; revert via a new appointment, not a status flip
- **Service Appointments are the schedulable unit.** Work Orders are containers; appointments are what dispatch sees. Don't put scheduling fields on the Work Order itself
- **Mirror status changes to associated records explicitly.** Closing a Work Order doesn't auto-close its appointments — that's project automation, typically a Flow

## FS-2: Service Appointments and Scheduling {#fs-service-appointments}

Service Appointments carry the `EarliestStartTime`, `DueDate`, `Duration`, `ServiceTerritory`, and `AssignedResource`. The Salesforce Scheduling Engine consumes these plus skill/territory/availability constraints to produce a schedule. Build the appointment correctly and the engine does the matching.

```apex
public with sharing class FieldServiceAppointmentBuilder {

    public static ServiceAppointment buildFromWorkOrder(WorkOrder wo, Datetime earliestStart) {
        ServiceAppointment sa = new ServiceAppointment(
            ParentRecordId   = wo.Id,
            ServiceTerritoryId = wo.ServiceTerritoryId,
            EarliestStartTime  = earliestStart,
            DueDate           = earliestStart.addHours(wo.Duration != null ? Integer.valueOf(wo.Duration) : 4),
            Duration          = wo.Duration,
            DurationType      = wo.DurationType,
            Subject           = wo.Subject,
            // SchedStartTime / SchedEndTime are populated by the scheduling engine
            ArrivalWindowStartTime = null,
            ArrivalWindowEndTime   = null
        );
        return sa;
    }

    /** Required Skills are how the engine matches resources. Always set on the WO line. */
    public static SkillRequirement requireSkill(Id workOrderLineItemId, Id skillId, Decimal level) {
        return new SkillRequirement(
            RelatedRecordId = workOrderLineItemId,
            SkillId         = skillId,
            SkillLevel      = level
        );
    }
}
```

**Rules**:
- **`EarliestStartTime` and `DueDate` are required for scheduling.** Without them the engine refuses to schedule
- **`SchedStartTime` / `SchedEndTime` are engine-owned.** Apex should not set them directly except in maintenance scripts
- **`SkillRequirement` records drive resource matching.** Skill on the line item, not the work order, when granular dispatch matters
- **Service Territory drives time-zone math.** Schedule arithmetic without the territory's time zone produces silently wrong assignments
- **Don't bypass `as user` DML on Service Appointments.** Customer Communities expose them; FLS surprises wreck dispatcher screens

## FS-3: Resource Absences and Operating Hours {#fs-availability}

Resource availability is the join of three things: `OperatingHours` (territory-level shift), `ServiceResource.IsActive`, and `ResourceAbsence` (out-of-office windows). The scheduler treats these as hard constraints; bypassing them in Apex by direct status flips creates double-bookings.

```apex
public with sharing class FieldServiceAvailability {

    /** Reserve a resource's PTO. The scheduler will not assign appointments overlapping. */
    public static ResourceAbsence reserveAbsence(Id resourceId, Datetime start, Datetime endsAt, String reason) {
        return new ResourceAbsence(
            ResourceId  = resourceId,
            Start       = start,
            End         = endsAt,
            Type        = 'Personal Time Off',
            Description = reason,
            IsConfirmed = true
        );
    }

    /** Operating hours are reusable; clone them per territory rather than authoring per-resource. */
    public static List<TimeSlot> standardWeekdayHours(Id operatingHoursId) {
        List<TimeSlot> slots = new List<TimeSlot>();
        for (String day : new List<String>{'Monday','Tuesday','Wednesday','Thursday','Friday'}) {
            slots.add(new TimeSlot(
                OperatingHoursId = operatingHoursId,
                DayOfWeek        = day,
                StartTime        = Time.newInstance(8, 0, 0, 0),
                EndTime          = Time.newInstance(17, 0, 0, 0)
            ));
        }
        return slots;
    }
}
```

**Rules**:
- **Always create a `ResourceAbsence` for PTO.** Don't toggle `IsActive` — that hides the resource from analytics and reporting too
- **`IsConfirmed = false` lets the dispatcher review.** Use it for self-service PTO requests; the engine still respects unconfirmed absences for scheduling
- **`OperatingHours` is template-shaped.** Define once per shift pattern, attach to many territories; don't author per-resource shifts unless they truly differ
- **Time zones are territory-bound.** A resource working in two territories needs two service-territory-member rows, not a single row with a fudged TZ
- **Use `as user` DML.** Self-service PTO from a portal needs FLS-aware writes; otherwise non-admins silently fail to insert

## FS-4: Mobile Offline Considerations {#fs-mobile-offline}

The Field Service Mobile app caches a subset of records on the device and syncs when network is available. Custom objects and Apex actions exposed to mobile must be **briefcase-aware**: small payload, predictable conflict resolution, idempotent on server replay.

```apex
public with sharing class FieldServiceMobileActions {

    /** Briefcase-friendly Apex action: returns only what the technician needs offline. */
    @AuraEnabled(cacheable=true)
    public static List<WorkOrderDigest> getMyAssignments(Id userId, Datetime windowStart, Datetime windowEnd) {
        // Project the minimum useful fields; large payloads break sync on bad networks
        return new WorkOrderDigest.Builder()
            .forUser(userId)
            .between(windowStart, windowEnd)
            .build();
    }

    /** Idempotent sync action — accepts a client-supplied externalKey so the server
     *  can dedup retries triggered by flaky cellular networks. */
    @AuraEnabled
    public static Id submitChecklistResult(String externalKey, String workOrderId, String checklistJson) {
        Field_Checklist_Result__c existing = [
            SELECT Id FROM Field_Checklist_Result__c
            WHERE External_Key__c = :externalKey
            WITH USER_MODE LIMIT 1
        ];
        if (existing != null) return existing.Id;  // dedup retried submission

        Field_Checklist_Result__c r = new Field_Checklist_Result__c(
            External_Key__c = externalKey,
            Work_Order__c   = workOrderId,
            Payload_JSON__c = checklistJson
        );
        insert as user r;
        return r.Id;
    }
}
```

**Rules**:
- **Server actions must be idempotent.** The mobile app retries on network blips; if the action isn't dedup-aware, the technician submits the same checklist twice
- **Project minimal fields offline.** Briefcase serves a fixed quota; don't push all 80 fields when the technician needs 12
- **Last-write-wins is the default; check before relying on it.** For multi-actor records (technician + dispatcher), introduce a `Last_Modified_By_Source__c` to disambiguate the conflict
- **Don't expose long-running async actions to mobile.** Apex callouts >10s are routinely abandoned by the mobile app on poor networks
- **Use `cacheable=true`** for read methods so the wire layer caches in-app, reducing rebuild churn after each sync cycle

## FS-5: Service Territory Design {#fs-territory}

Service Territories are the geographic + organizational unit that drives scheduling. Operating hours, default skills, and territory members all attach here. Hierarchical territories (parent/child) inherit operating hours; flat territories don't. Pick the model based on whether business owners need rollups.

```apex
public class ServiceTerritoryFactory {

    /** Create a child territory inheriting operating hours from a parent. */
    public static ServiceTerritory createRegional(String name, Id parentTerritoryId, Id operatingHoursId) {
        return new ServiceTerritory(
            Name             = name,
            ParentTerritoryId = parentTerritoryId,
            OperatingHoursId = operatingHoursId,
            IsActive         = true
        );
    }

    /** Add a resource to a territory with a primary/secondary flag. */
    public static ServiceTerritoryMember addResource(Id territoryId, Id resourceId, Boolean primary) {
        return new ServiceTerritoryMember(
            ServiceTerritoryId = territoryId,
            ServiceResourceId  = resourceId,
            TerritoryType      = primary ? 'P' : 'S',  // Primary or Secondary
            EffectiveStartDate = Date.today()
        );
    }
}
```

**Rules**:
- **One Primary territory per resource.** Multiple primaries confuse the engine and double-count capacity in reports
- **Hierarchical territories simplify operating-hours management.** Define hours at the top, override per child only when actually different
- **Territories aren't a substitute for skills.** Geography and skill are orthogonal; a resource in California with electrician skill is different from one with plumber skill
- **`EffectiveStartDate` / `EffectiveEndDate` matter for analytics.** Mid-year reorgs need new territory-member rows, not edits in place
- **Test territory changes with a real schedule.** Removing a resource from a territory mid-week with appointments scheduled there orphans those appointments; the engine doesn't auto-reassign

---

## Anti-patterns

- **Hardcoding Work Order status labels in Apex.** Customers rename them; key off `Status.Category` instead
- **Skipping `ResourceAbsence` and just toggling `IsActive`.** Hides the resource everywhere, including reporting; use `ResourceAbsence` for time-bounded unavailability
- **Putting scheduling fields on the Work Order.** Service Appointment is the schedulable unit; Work Order is the container
- **Pushing every WO field to mobile briefcase.** Quota fills up with low-value fields; sync time balloons. Project deliberately
- **Non-idempotent mobile sync actions.** Cell-network retries become duplicate inserts. Always carry an `External_Key__c` for dedup
- **Multi-primary territory membership.** Engine assumes one primary; multiple primaries inflate reported capacity and break dispatch heuristics
- **Manual `SchedStartTime` writes from Apex.** The engine owns those; manual writes get overwritten on the next optimization run
- **Authoring per-resource operating hours.** Use template `OperatingHours` records and attach via `ServiceTerritoryMember`; per-resource hours are an admin nightmare
