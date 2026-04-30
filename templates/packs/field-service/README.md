# Field Service Pack

Patterns for **Salesforce Field Service** — work order lifecycle, scheduling and dispatch, mobile offline behavior, service territories, and resource availability.

## When to use this pack

Install with `/argo:pattern-pack add field-service` if your project:
- Manages Work Orders, Service Appointments, and Service Resources
- Customizes the Field Service Mobile experience for technicians
- Integrates the Salesforce Scheduling Engine with custom skill or territory logic
- Builds dispatch / scheduling UIs over the standard objects

Don't install for:
- Pure case-management workflows (use base SF patterns + Service Cloud features)
- One-off appointment booking (Salesforce Scheduler is the simpler product)

## What's in the pack

- **FS-1: Work Order Lifecycle Modeling** — status categories, transitions metadata, lifecycle rules
- **FS-2: Service Appointments and Scheduling** — `EarliestStartTime` / `DueDate` / SkillRequirement, engine ownership of `SchedStartTime`
- **FS-3: Resource Absences and Operating Hours** — `ResourceAbsence`, `OperatingHours`, `TimeSlot`, territory time-zone math
- **FS-4: Mobile Offline Considerations** — briefcase awareness, idempotent actions, conflict resolution
- **FS-5: Service Territory Design** — hierarchical vs flat, Primary/Secondary membership, effective dating

Plus checklist items covering status modeling, scheduling-engine ownership, PTO patterns, mobile retry semantics, and territory hygiene.

## What's not in the pack

- Salesforce Scheduler (a different product) — see Salesforce's Scheduler-specific guidance
- Field Service Lightning v1 (legacy) — the patterns assume v2/Field Service core API ≥ 60.0
- Maps / geocoding integrations — use a Named Credential and SF-15

## Cross-references

- Base patterns: SF-7 (Trigger Handler Framework — Service Appointment lifecycle triggers), SF-15 (Named Credentials — for geocoding callouts), SF-19 (Virtualized List — for dispatcher screens with thousands of appointments)
- Specialist agents: `@data-architect` for territory design, `@apex-dev` for triggers/queueables, `@lwc-dev` for dispatcher UIs

## References

- [Field Service Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.field_service_dev.meta/field_service_dev/)
- [Service Appointment Object Reference](https://developer.salesforce.com/docs/atlas.en-us.api.meta/api/sforce_api_objects_serviceappointment.htm)
- [Briefcase Builder (mobile offline)](https://help.salesforce.com/s/articleView?id=sf.briefcase_overview.htm)
