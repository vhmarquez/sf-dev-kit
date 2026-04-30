---
name: security-scan
description: Run PMD with the Apex security ruleset against the project's Apex source. Surfaces SOQL injection vectors, missing CRUD/FLS checks, hardcoded credentials, sharing violations, and other Apex-specific security issues. CI mode emits SARIF for GitHub Code Scanning.
data-access: none
---

You are running a **security scan** of the Apex source. The scan uses [PMD](https://pmd.github.io/) with its `apex-security` ruleset (built-in to PMD 7.x). PMD is downloaded on first use into the plugin data directory.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/pmd.sh"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
```

## Input

`$ARGUMENTS`:
- (empty) — scan the entire Apex source directory
- `<ClassName>` — scan one class
- `<path>` — scan a specific path
- `--ruleset <name>` — additional rulesets beyond `apex-security` (e.g., `apex-bestpractices`, `apex-performance`, `apex-codestyle`). Comma-separated. Default is `apex-security` only
- `--baseline <path>` — diff against a baseline scan; only report new findings (Phase 8 builds on this)
- `--ci` — machine output
- `--format json|sarif` (default `sarif` in CI mode)
- `--out <path>` — output file

## Steps

### 1. Ensure PMD is installed
```bash
pmd_install || exit 2
```
First call downloads PMD; subsequent calls reuse the cache.

### 2. Build the ruleset arg

PMD 7.x reference categories:
- `category/apex/security.xml` — SOQL injection, CRUD/FLS, hardcoded URLs, weak randomness, etc.
- `category/apex/bestpractices.xml`
- `category/apex/performance.xml`
- `category/apex/codestyle.xml`
- `category/apex/design.xml`
- `category/apex/errorprone.xml`
- `category/apex/documentation.xml`

Default: `category/apex/security.xml` only.

### 3. Run PMD

```bash
pmd_run check \
  --dir "$APEX_SRC" \
  --rulesets "category/apex/security.xml${EXTRA:+,$EXTRA}" \
  --format json \
  --report-file /tmp/security-scan.pmd.json \
  --no-progress
```

Capture exit code separately — PMD exits non-zero on findings, which is expected.

### 4. Convert PMD output to internal finding shape

Map each PMD violation to:
```json
{
  "ruleId":   "SEC-${PMD_RULE_NAME}",
  "severity": "error|warning|note",  // map from PMD priority 1-2 → error, 3 → warning, 4-5 → note
  "message":  "<PMD description>",
  "file":     "<relative path>",
  "line":     <beginline>,
  "endLine":  <endline>,
  "ruleHelpUri": "https://docs.pmd-code.org/.../<rule>.html",
  "tool":     "security-scan"
}
```

Common rules in `apex-security` (mapped IDs):
| PMD rule | Mapped | Severity |
|----------|--------|----------|
| ApexBadCrypto | `SEC-BAD-CRYPTO` | error |
| ApexCRUDViolation | `SEC-CRUD-VIOLATION` | error |
| ApexInsecureEndpoint | `SEC-INSECURE-ENDPOINT` | error |
| ApexOpenRedirect | `SEC-OPEN-REDIRECT` | error |
| ApexSharingViolations | `SEC-SHARING-VIOLATION` | error |
| ApexSOQLInjection | `SEC-SOQL-INJECTION` | error |
| ApexSuggestUsingNamedCred | `SEC-USE-NAMED-CRED` | warning |
| ApexXSSFromEscapeFalse | `SEC-XSS-ESCAPE-FALSE` | error |
| ApexXSSFromURLParam | `SEC-XSS-URL-PARAM` | error |
| ApexDangerousMethods | `SEC-DANGEROUS-METHODS` | error |

### 5. Output

Default Markdown (one report per scan):
```
# Security Scan: <project.name>

Scanned: 47 Apex files
PMD: 7.6.0 | Ruleset: apex-security
Run at: 2026-04-28T12:45:00Z

## Findings

### Critical (3)
- `SEC-SOQL-INJECTION` — force-app/.../OrderController.cls:42 — Dynamic SOQL with unescaped user input
- ...

### High (5)
- `SEC-CRUD-VIOLATION` — force-app/.../OrderService.cls:84 — Missing CRUD check before insert
- ...

### Medium (8)
- `SEC-USE-NAMED-CRED` — force-app/.../OldClient.cls:12 — Endpoint hardcoded; use Named Credential (SF-15)
- ...

## Pattern compliance reminders
- SF-15: HTTP callouts via Named Credential
- SF-11: Dynamic field-name whitelist before SOQL composition
- SF-17: Custom Metadata Type lookup; do not put credentials in Custom Settings

(See ${paths.patternsSalesforceDoc} for full pattern docs.)
```

CI mode: pipe internal findings through `sarif_emit "argo/security-scan" "$VERSION"`.

### 6. Exit codes
- 0 — no findings
- 1 — any error or warning findings
- 2 — PMD failed to run

## Rules

- **Don't auto-fix.** This scan is a report; the user reads and fixes
- **Don't run on test classes** by default — they're allowed to violate sharing for setup. Skip `*<testSuffix>.cls`
- **Honor `.pmd-suppressions.xml`** if the user adds one — PMD reads it natively
- **Don't shadow @qa.** This scan is narrower (Apex security only) than `/code-review`; both should be run
- **Update PMD version pinning intentionally.** New PMD versions add rules — never silently upgrade. Pin in `hooks/lib/pmd.sh` and bump in a chore commit

## Consumers

- `/argo:code-review` and `@qa` recommend running `/security-scan` for any class touching DML, callouts, or dynamic SOQL
- CI pipelines run `/security-scan --ci --format sarif --out scan.sarif` and upload to GitHub Code Scanning
- `@security-reviewer` (Phase 5) reads scan results to focus its analysis
