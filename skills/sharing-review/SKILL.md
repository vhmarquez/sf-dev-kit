---
name: sharing-review
description: List every Apex class declared `without sharing` or `inherited sharing` and require/verify a justification comment. Catches accidental privilege escalation in service classes.
---

You are reviewing **sharing keywords** on Apex classes. The platform default for new classes should match `platform.sharingDefault` from config (typically `with sharing`). Any deviation must be intentional and justified inline.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
SHARING_DEFAULT="$(sf_config_get '.platform.sharingDefault' "$ENV")"
TEST_SUFFIX="$(sf_config_get '.naming.apex.testSuffix' "$ENV")"
```

## Input

`$ARGUMENTS`:
- (empty) — review every class
- `<ClassName>` — single class
- `--ci` / `--format json|sarif` / `--out <path>`

## Steps

### 1. Walk Apex source

For each `.cls`:
- Capture the class declaration line: `(public|global|private)\s+(virtual\s+)?(?:abstract\s+)?(?:with|without|inherited)\s+sharing\s+class\s+(\w+)` (or no sharing keyword at all → defaults to `with sharing` for top-level classes; see [Apex docs](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_classes_keywords_sharing.htm))
- Skip test classes unless `--include-tests`

### 2. Classify

| Pattern | Verdict | Rule ID |
|---------|---------|---------|
| `with sharing` and matches `SHARING_DEFAULT` | ✅ ok | — |
| (no sharing keyword) | ✅ ok (defaults to `with sharing`) but suggest making explicit | `SHR-IMPLICIT-SHARING` (note) |
| `inherited sharing` | ✅ ok if used as utility called from `with sharing` callers | `SHR-INHERITED-SHARING` (note) |
| `without sharing` and no justification comment within 5 lines above | ⚠️ warning | `SHR-WITHOUT-SHARING-NO-JUSTIFICATION` |
| `without sharing` with justification comment | ✅ acknowledged | `SHR-WITHOUT-SHARING` (note) |

A "justification comment" is a line within 5 lines above the class declaration matching:
```regex
//\s*(?:reason|why|justification):\s*\S+
```

### 3. Cross-check usage

For every `without sharing` class, find callers via grep:
```bash
grep -lE "\b<ClassName>\." "${APEX_SRC}"/*.cls "${APEX_SRC}"/*.trigger
```
Flag a `without sharing` class only called from `with sharing` callers — that's safe. Flag with elevated severity any `without sharing` class called from `@AuraEnabled` methods (those run as the user; the privilege escalation is the bug).

### 4. Output

Default Markdown:
```
# Sharing Review: <project.name>

Sharing default: with sharing
Classes scanned: 47 production
Run at: 2026-04-28T13:15:00Z

## Findings

### Critical (without sharing called from @AuraEnabled) — 1
- `force-app/.../AdminUtils.cls` (`without sharing`) is called from
  `OrderController.createOrder` (@AuraEnabled). This bypasses the user's
  sharing rules at LWC entry. Add an explicit access check or move the
  privileged code behind a server-only entry point. (SHR-WITHOUT-SHARING-AURA-ESCAPE)

### Warning (without sharing without justification) — 2
- `force-app/.../LegacyJob.cls` — declare a justification comment:
    // reason: scheduled job runs as system; needs cross-org visibility
- `force-app/.../OldHelper.cls` — same

### Note (without sharing with justification) — 3
- `force-app/.../IntegrationUser.cls` // reason: integration user has restricted profile; sharing not applicable
- ...

### Note (implicit `with sharing`) — 12
- (consider adding the explicit keyword for clarity)
```

CI mode: emit findings via SARIF.

### 5. Exit codes
- 0 — no findings (or only `note` severity)
- 1 — any warning or error
- 2 — config error

## Rules

- **Justification comments must be specific.** "// reason: legacy" is not enough. Look for either a referenced ticket / ADR or a domain-specific reason
- **AuraEnabled escape is the worst case.** A `without sharing` class touched by an `@AuraEnabled` method bypasses the user's sharing rules — that's almost always wrong. Treat as `error`
- **`inherited sharing` is fine for utilities.** It defers to the calling class and matches the principle of least surprise
- **Don't include test classes** unless `--include-tests`
- **Don't auto-rewrite.** Sharing changes are operational decisions; the user makes them

## Consumers

- `@security-reviewer` reads this skill's findings as part of its review
- `/sf-dev-kit:code-review` cross-links to this skill when it sees a class touch DML
- ADRs may justify a `without sharing` choice — `/adr` linkable from the justification comment
