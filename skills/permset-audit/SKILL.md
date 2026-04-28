---
name: permset-audit
description: Build a permission audit matrix mapping every object/field in the target org to the profiles and permission sets that grant access. Flag orphan permsets, profile-vs-permset CRUD divergence, and fields with no read access from any profile/permset.
---

You are building a **permission audit matrix** for the target org. The matrix is rows=objects/fields, columns=profile-or-permset, cells=`R/CRUD/-`. Use it to spot orphan permsets, fields that no one can see, and divergence between similarly named profiles and permsets.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/sf-cli.sh"
sf_cli_check || exit 2
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
```

## Input

`$ARGUMENTS`:
- (empty) — full audit of all custom objects + selected standard objects (Account, Contact, Case, Opportunity, Lead, User)
- `<object>` — limit to a single sObject API name
- `<object>.<field>` — limit to a single field
- `--include-managed` — include objects from managed packages (default: skip)
- `--target-org <alias>` / `--env <name>` — standard overrides
- `--ci` / `--format json|sarif` / `--out <path>`

## Steps

### 1. Pull profiles, permsets, and assignments
```bash
sf data query --target-org "$ORG" --json --query "
  SELECT Id, Name, UserType, IsCustom FROM Profile
" > /tmp/permset-audit-profiles.json

sf data query --target-org "$ORG" --json --query "
  SELECT Id, Name, Label, License.Name, Type, IsCustom
  FROM PermissionSet
  WHERE IsOwnedByProfile = false
" > /tmp/permset-audit-permsets.json

sf data query --target-org "$ORG" --json --query "
  SELECT AssigneeId, PermissionSetId
  FROM PermissionSetAssignment
  WHERE PermissionSet.IsOwnedByProfile = false
" > /tmp/permset-audit-assignments.json
```

### 2. Pull object permissions
For the in-scope objects:
```bash
sf data query --target-org "$ORG" --json --query "
  SELECT ParentId, Parent.Name, Parent.Type, Parent.Profile.Name,
         SObjectType, PermissionsRead, PermissionsCreate, PermissionsEdit,
         PermissionsDelete, PermissionsViewAllRecords, PermissionsModifyAllRecords
  FROM ObjectPermissions
  WHERE SObjectType IN ('Account','Contact', ...)
"
```

### 3. Pull field permissions (per object — paginate)
```bash
sf data query --target-org "$ORG" --json --query "
  SELECT ParentId, Parent.Name, Parent.Type, Parent.Profile.Name,
         SObjectType, Field, PermissionsRead, PermissionsEdit
  FROM FieldPermissions
  WHERE SObjectType = 'Account'
"
```
FieldPermissions queries are large; loop per object instead of one giant IN clause.

### 4. Build the matrix in memory

Pseudocode:
```python
matrix = {}  # (sobject, field) -> { permsetId -> "R" / "CRUD" / "-" }
for fp in field_permissions:
    key = (fp.sobject, fp.field)
    matrix.setdefault(key, {})
    cell = matrix[key]
    perms = []
    if fp.PermissionsEdit: perms.append("U")
    if fp.PermissionsRead: perms.append("R")
    cell[fp.parent_id] = "".join(perms) or "-"
```

Repeat for object-level perms.

### 5. Findings

- **`PERM-ORPHAN-PERMSET`** *(warning)* — permset not assigned to any user, never granted access to any object/field used by any LWC/Apex in source
- **`PERM-FIELD-NO-READ`** *(error)* — custom field with **no** profile or permset granting read; nobody can see it
- **`PERM-DIVERGENCE`** *(warning)* — profile and similarly-named permset both grant access to the same object but with different CRUD masks (likely accidental)
- **`PERM-MASTER-DETAIL-NO-CRU`** *(warning)* — master object grants edit but child master-detail object doesn't (or vice versa) — likely a misconfigured share path

### 6. Output

Default Markdown:
```
# Permission Audit: <ORG>

Run at: ...
Scope: 27 custom objects + 6 standard

## Findings

### Critical (must fix)
- `Account.Risk_Score__c` — no profile or permset grants Read access (PERM-FIELD-NO-READ)
- ...

### High
- Permset `Sales_Old` is unassigned and grants no source-referenced access (PERM-ORPHAN-PERMSET)
- ...

## Coverage matrix excerpt: Account

| Field | Sales User | Sales Manager | Acme_Sales_PS | Acme_Manager_PS |
|-------|------------|----------------|----------------|-------------------|
| Name  | R          | RU             | RU             | RU                |
| Risk_Score__c | -  | -              | RU             | RU                |
| ...

(Full matrix in CI JSON output.)
```

CI JSON shape:
```json
{
  "org": "...", "ranAt": "...",
  "findings": [{ "ruleId": "PERM-FIELD-NO-READ", "severity": "error", "message": "...", "file": "(metadata)", "line": 1 }],
  "matrix": {
    "Account": {
      "Name": { "Sales User": "R", "Acme_Sales_PS": "RU" },
      "Risk_Score__c": { "Acme_Sales_PS": "RU" }
    }
  }
}
```

SARIF: each finding emitted via `${CLAUDE_PLUGIN_ROOT}/hooks/lib/sarif.sh`. The matrix is omitted from SARIF (SARIF is for findings, not data) — emit JSON sidecar at `<out>.matrix.json`.

### 7. Exit codes
- 0 — no error-level findings
- 1 — any error-level finding
- 2 — query/setup error

## Rules

- **No write operations.** This is read-only; never deploy or modify perms
- **Page large queries.** FieldPermissions on a heavy org can return tens of thousands of rows — paginate per sObject
- **Excluded by default**: managed-package objects (`namespacePrefix` set), the `User` object's standard fields, and audit fields (`CreatedDate`, etc.)
- **Skip system permsets.** `IsOwnedByProfile = true` permsets are profile-derived; we only audit user-managed permsets
