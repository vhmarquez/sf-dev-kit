---
name: flow-audit
description: Inventory active Flows in the target org, classify them by trigger type and purpose, flag overlaps with Apex triggers in source, and surface flows that lack source-control coverage. Useful before recommending new automation (Flow vs. Trigger decision) and during automation audits.
data-access: metadata-only
---

You are auditing record-triggered, screen, scheduled, and platform-event Flows in the target org. Output a structured report so the user — or `@architect` — can decide how to consolidate, replace, or leave them alone.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/sf-cli.sh"
sf_cli_check || exit 2
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
```

## Input

`$ARGUMENTS`:
- (empty) — full audit of active Flows
- `<object>` — limit to flows that target a specific sObject (e.g., `Account`)
- `--include-inactive` — include inactive flow versions in the inventory
- `--target-org <alias>` / `--env <name>` — standard overrides
- `--ci` / `--format json|sarif` / `--out <path>` — see CI output contract

## Steps

### 1. Inventory active Flows

```bash
sf data query --target-org "$ORG" --json --query "
  SELECT DeveloperName, Label, ProcessType, TriggerType, TriggerObjectOrEvent.QualifiedApiName,
         ActiveVersion.VersionNumber, ActiveVersion.Status,
         LastModifiedBy.Name, LastModifiedDate, ManageableState
  FROM FlowDefinitionView
  WHERE IsActive = TRUE
  ORDER BY TriggerType, TriggerObjectOrEvent.QualifiedApiName, DeveloperName
"
```

If `<object>` was provided, add `AND TriggerObjectOrEvent.QualifiedApiName = '<object>'`.

### 2. Classify by ProcessType + TriggerType

| ProcessType | Meaning | Notes |
|-------------|---------|-------|
| `AutoLaunchedFlow` + `RecordBeforeSave` | Before-save record-triggered flow | Pre-DML field set; same-record updates only, no callouts |
| `AutoLaunchedFlow` + `RecordAfterSave` | After-save record-triggered flow | Cross-object DML, async; high concurrency risk |
| `AutoLaunchedFlow` + `Scheduled` | Scheduled flow | Runs on a schedule; check frequency |
| `Flow` | Screen flow | User-facing, requires visibility into the app/page |
| `AutoLaunchedFlow` + `PlatformEvent` | Platform-event-triggered flow | Subscriber to a Platform Event |
| `Workflow` | Legacy Workflow Rule (auto-migrated) | Retire in favor of Flow |
| `ProcessBuilder` | Process Builder (deprecated) | Retire — Salesforce has end-of-life dates |

### 3. Detect Apex-trigger / Flow overlaps

For each record-triggered Flow on object `O`:
```bash
grep -l "trigger .* on $O " "$APEX_SRC"/*.trigger 2>/dev/null
```
If overlap, flag:
- Both Flow and Apex Trigger run on the same object → unpredictable order, governor-limit risk
- Recommend: consolidate (use one or the other), or document the order if both must coexist

### 4. Detect orphan flows (no source coverage)

Cross-reference flow `DeveloperName` against `force-app/**/flows/*.flow-meta.xml`:
- Active in org **AND** present in source — ✅ tracked
- Active in org **AND NOT** in source — ⚠️ untracked (will not deploy elsewhere; missing from CI/CD)
- In source **AND NOT** active — ✅ deactivated; possibly intentional

### 5. Output

Default Markdown report:

```
# Flow Audit: <ORG>

Run at: 2026-04-28T10:40:00Z
Active flows: 12

## Active record-triggered flows

| DeveloperName | Object | TriggerType | Modified by | In source? | Apex overlap? |
|---------------|--------|-------------|-------------|------------|---------------|
| Acct_Set_Region_AfterSave | Account | RecordAfterSave | jdoe@... | ✅ | ⚠️ AccountTrigger |
| Case_Auto_Assign | Case | RecordBeforeSave | gov-user | ❌ untracked | — |

## Active screen flows

| DeveloperName | Label | Modified by | In source? |
|---------------|-------|-------------|------------|
| ...

## Active scheduled flows

| DeveloperName | Frequency | Last modified | In source? |
|---------------|-----------|---------------|------------|

## Active platform-event flows

...

## Findings

### ⚠️ Untracked active flows (3)
These run in production but aren't in source control:
- `Case_Auto_Assign` — last modified 2026-04-15 by gov-user
- ...

### ⚠️ Apex/Flow overlaps (1)
Same-object automation in two technologies:
- Account: `Acct_Set_Region_AfterSave` (Flow) + `AccountTrigger` (Apex)

### ⚠️ Deprecated automation in use (2)
- `Old_Process_Builder_X` (ProcessBuilder) — Salesforce end-of-life
- `Workflow_Auto_Email` (Workflow) — migrate to Flow
```

CI mode emits findings in the internal shape (see `docs/ci-output-contract.md`):
- `FLOW-UNTRACKED` — `warning` per untracked active flow
- `FLOW-APEX-OVERLAP` — `warning` per same-object overlap
- `FLOW-DEPRECATED` — `error` for ProcessBuilder/Workflow

### 6. Exit codes
- 0 — no findings
- 1 — any `FLOW-*` findings
- 2 — query/setup error

## Rules

- **Don't try to read flow contents.** Flow XML parsing is heavy; this skill is metadata-only. Use `/sf-dev-kit:field-impact` if you need to know which fields a Flow touches
- **Don't audit inactive flows by default.** They're harmless and noisy
- **Honor managed packages.** Flows from a managed package (`ManageableState != 'unmanaged'`) are not the user's concern; report them in a separate "From Managed Packages" section
- **No row counts in the report unless you queried for them.** Run-history queries are expensive and not always available; don't fake metrics
