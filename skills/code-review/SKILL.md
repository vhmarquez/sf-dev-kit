---
name: code-review
description: Perform a comprehensive code review of an LWC component, Apex class, or both against project standards
---

You are performing a code review for this Salesforce project. Assess code quality, identify issues, and highlight strengths — but make **no edits**.

## Read Project Config First

Always start by reading `.claude/sf-project.json` for paths, naming convention, and quality targets. References below to `{paths.lwcSource}`, `{naming.lwc.prefix}`, etc. resolve from that file.

## Input

The user provided: `$ARGUMENTS`

This could be:
- An LWC component name (matches the project's `naming.lwc.prefix`)
- An Apex class name
- A file path
- The word `both` followed by an LWC name (e.g., `both myComponent`) to review the LWC and all its Apex dependencies
- The word `all` — review every in-scope LWC component (see Batch Modes)
- The word `audit` — produce a single compliance matrix instead of per-component reviews (see Batch Modes)
- The word `pr` — review only files changed since `main` HEAD (see PR mode)

CI flags (per `${CLAUDE_PLUGIN_ROOT}/docs/ci-output-contract.md`):
- `--ci` — machine-readable output, exit codes per contract
- `--format json|sarif` — output format (default `json` in CI mode)
- `--out <path>` — write to file instead of stdout
- `--fail-on error|warning|note` — minimum severity that triggers exit 1 (default `error`)

## Steps

1. **Identify the target.** Determine if the input is an LWC, Apex class, or both. If a component name is given without a path, search in `{paths.lwcSource}` and `{paths.apexSource}`.

2. **Read all source files.**
   - For LWC: Read the `.js`, `.html`, `.css`, and `.js-meta.xml` files
   - For Apex: Read the `.cls` file
   - If reviewing "both" or if the LWC imports Apex controllers, read those controllers too

3. **Read the project standards.** These are critical — review against them:
   - `docs/patterns/salesforce-patterns.md` — generic platform patterns
   - `docs/patterns/project-patterns.md` — project-specific patterns and shared components
   - `docs/lwc-standards.md` — CSS, JS, and accessibility rules (for LWC reviews)
   - `docs/apex-standards.md` — Governor limits, SOQL, DML, security rules (for Apex reviews)
   - `docs/quality-checklist.md` — Unified quality checklist
   - `docs/project-context.md` — Object model and channel context

4. **Read existing documentation** for the component if it exists in `{paths.lwcDocs}` or `{paths.apexDocs}` to check whether the docs are still accurate.

5. **Produce the review report** using the format below.

6. **Save the review report** to the `code-reviews/` directory in the project root.
   - File name: `{ComponentName}.md`
   - If reviewing "both", use the LWC name
   - Overwrite if the file already exists
   - Create the `code-reviews/` directory if it doesn't exist

## Review Report Format

```
## Code Review: {ComponentName}

### Summary
(1-2 sentences: what this component does and overall assessment)

### Strengths
- (Things done well — be specific, reference line numbers or patterns followed)

### Issues

#### Critical (must fix — security, data loss, broken functionality)
- (or "None")

#### High (should fix — governor limits, performance, accessibility gaps)
- (or "None")

#### Medium (recommended — maintainability, pattern compliance, code clarity)
- (or "None")

#### Low (nice to have — naming, minor style, documentation drift)
- (or "None")

### Pattern Compliance
| Pattern | Source | Applies? | Followed? | Notes |
|---------|--------|----------|-----------|-------|
| Paginated Datatable | SF-1 | Yes/No | ✅/❌/Partial | (details) |
| Record Detail View | SF-2 | Yes/No | ✅/❌/Partial | (details) |
| LMS Subscription Lifecycle | SF-3 | Yes/No | ✅/❌/Partial | (details) |
| XML Meta Config | SF-4 | Yes/No | ✅/❌/Partial | (details) |
| Paginated Apex Controller | SF-5 | Yes/No | ✅/❌/Partial | (details) |
| AuraEnabled Methods | SF-6 | Yes/No | ✅/❌/Partial | (details) |
| Trigger Handler Framework | SF-7 | Yes/No | ✅/❌/Partial | (details) |
| Toast Notifications | SF-8 | Yes/No | ✅/❌/Partial | (details) |
| Wrapper / DTO Classes | SF-9 | Yes/No | ✅/❌/Partial | (details) |
| Confirmation Dialog | SF-10 | Yes/No | ✅/❌/Partial | (details) |
| Filter Whitelist | SF-11 | Yes/No | ✅/❌/Partial | (details) |
| Apex Inline Docs | SF-12 | Yes/No | ✅/❌/Partial | (details) |
| LWC Inline Docs | SF-13 | Yes/No | ✅/❌/Partial | (details) |
| (Any project-specific patterns from project-patterns.md that apply) | PRJ-N | Yes/No | ✅/❌/Partial | (details) |

### Documentation Status
- (Is the doc file up to date with the current code? Flag any drift.)

### Suggestions
- (Optional improvements that aren't strictly issues — performance optimizations, refactoring ideas, accessibility enhancements)
```

## Review Checklist

Assess all applicable items from **`docs/quality-checklist.md`** — the unified quality checklist.

For LWC reviews, check: JavaScript, CSS, HTML/Accessibility, and Meta XML sections.
For Apex reviews, check: Security, Governor Limits, Error Handling, and Code Quality sections.
For "both" reviews, check all sections.

## CI Mode

In CI mode (`--ci`), produce findings in the internal shape (see `docs/ci-output-contract.md`) instead of the Markdown report:

```json
[
  {
    "ruleId": "SF-5",
    "severity": "warning",
    "message": "Paginated controller missing the count companion method",
    "file": "force-app/main/default/classes/OrderController.cls",
    "line": 42,
    "ruleHelpUri": "<patternsSalesforceDoc>#paginated-controller",
    "tool": "code-review"
  }
]
```

For SARIF output, source `${CLAUDE_PLUGIN_ROOT}/hooks/lib/sarif.sh` and pipe through `sarif_emit "sf-dev-kit/code-review" "<plugin-version>"`.

Exit codes (per contract):
- 0 — no findings at or above `--fail-on` threshold
- 1 — findings at or above the threshold
- 2 — invocation error

Rule ID prefixes used by code-review:
- `SF-N` / `PRJ-N` — pattern-compliance findings (matches the pattern doc IDs)
- `LWC-*` — LWC-specific issues (e.g., `LWC-WIRE-IN-LOOP`)
- `APEX-*` — Apex-specific issues not covered by /security-scan or /fls-audit

## PR Mode

Invoked as `/sf-dev-kit:code-review pr`:
1. Run `git diff --name-only main...HEAD` to find changed source files
2. For each changed file, dispatch into the per-file review path
3. Aggregate findings; emit a single report (Markdown or CI JSON)
4. Useful in CI as the gate on PR merges

## Batch Modes

### `all` — Review all in-scope components

When the input is `all`:
1. List all directories in `{paths.lwcSource}` matching `{naming.lwc.prefix}*` (or all directories if `naming.lwc.prefix` is empty), excluding any matching patterns in `naming.lwc.excludePrefixes`
2. For each component, run a full review and save to `code-reviews/{componentName}.md`
3. After all individual reviews, produce a summary at `code-reviews/SUMMARY.md`:
   - Table: component name, critical issues count, high issues count, overall assessment
   - Top 5 most common issues across all components
   - Components with the best/worst pattern compliance

### `audit` — Standards compliance matrix

When the input is `audit`:
1. List all in-scope LWC components and their Apex dependencies
2. For each, do a lightweight pass against `docs/quality-checklist.md` and both pattern docs
3. Produce a single compliance report at `code-reviews/AUDIT.md`:
   - Compliance matrix: rows = components, columns = patterns (SF-1 through SF-14, plus any PRJ-* that apply), cells = Pass/Fail/N/A
   - Summary of most common violations
   - Recommended priority fixes (grouped by category)
4. Do NOT produce individual review files — the audit is a summary-only pass

## Rules

- Be specific: reference file names and line numbers
- Be balanced: always include strengths, not just problems
- Be actionable: every issue should have a clear fix
- Do **NOT** edit any source code files — this is a read-only review of the codebase
- The only files you should write are review reports in `code-reviews/`
- If documentation is missing or outdated, flag it but don't create it
