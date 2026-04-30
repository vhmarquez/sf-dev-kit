---
name: complexity
description: Compute cyclomatic complexity per Apex method and per LWC JS function. Flags hotspots above a configurable threshold (default 10). Useful for spotting methods that need refactoring before they become unmaintainable.
data-access: none
---

You are computing **cyclomatic complexity (CC)** — the number of linearly independent paths through a function. CC of 1 = straight-line code, 5 = moderate, 10 = at the limit of "manageable", 15+ = needs refactoring.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/pmd.sh"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
LWC_SRC="$(sf_config_get '.paths.lwcSource' "$ENV")"
TEST_SUFFIX="$(sf_config_get '.naming.apex.testSuffix' "$ENV")"
```

PMD has built-in cyclomatic complexity rules — we delegate Apex CC to it. For LWC (JS), we count manually since PMD doesn't analyze JS.

## Input

`$ARGUMENTS`:
- (empty) — scan everything
- `apex` — Apex only
- `lwc` — LWC JS only
- `--threshold <n>` — flag complexity above N (default 10)
- `--ci` / `--format json|sarif` / `--out <path>`

## Steps

### Apex (via PMD)

```bash
pmd_run check \
  --dir "$APEX_SRC" \
  --rulesets "category/apex/design.xml" \
  --format json \
  --report-file /tmp/complexity.pmd.json \
  --no-progress
```

Filter the PMD output to rules:
- `CyclomaticComplexity` — primary
- `CognitiveComplexity` — secondary (related but distinct)
- `ExcessiveClassLength`, `ExcessiveMethodLength` — overflow indicators

Convert each to internal finding shape with `ruleId: "CPX-CYCLOMATIC"` (or `CPX-COGNITIVE`, etc.).

### LWC JS (heuristic counter)

For each `.js` file under `${LWC_SRC}` (excluding `__tests__`):
- For each function (declaration or arrow assigned to a property), count the following as +1:
  - `if`, `else if`
  - `case` in a switch
  - `for`, `while`, `do`
  - Ternary `? :`
  - Logical `&&`, `||` (short-circuit increases path)
  - `catch` block
  - Each top-level `return` after the first

Base complexity = 1; cap at 50 for sanity (anything beyond is pathological).

Report findings with `ruleId: "CPX-LWC-CYCLOMATIC"`, severity:
- 11–15: warning
- 16+: error

## Output

Default Markdown:
```
# Complexity Report: <project.name>

Threshold: 10
Apex methods analyzed: 412 (production, excluding tests)
LWC JS functions analyzed: 287
Run at: 2026-04-28T15:15:00Z

## Apex hotspots (top 10)

| File | Method | Cyclomatic | Cognitive | Length |
|------|--------|------------|-----------|--------|
| force-app/.../OrderProcessor.cls | processBulk | 22 ⚠️ | 31 ⚠️ | 145 lines |
| force-app/.../LegacyImporter.cls | importBatch | 18 ⚠️ | 26 ⚠️ | 110 lines |
| ...

## LWC hotspots (top 10)

| File | Function | Cyclomatic |
|------|----------|------------|
| force-app/.../acmeOrderForm/acmeOrderForm.js | handleSave | 13 ⚠️ |
| ...

## Refactoring suggestions
- `OrderProcessor.processBulk` (CC 22): extract per-record logic into a helper; the 22 paths likely collapse to a single switch over status
- `acmeOrderForm.handleSave` (CC 13): split validation, persistence, and side-effects into separate methods

## Distribution
- ≤5 (good):     312 methods (76%)
- 6–10 (ok):      87 methods (21%)
- 11–15 (warn):   11 methods  (3%)
- 16+ (error):     2 methods  (1%)
```

CI: SARIF per finding with severity mapped from threshold bands.

## Exit codes
- 0 — no findings above threshold
- 1 — any finding above threshold
- 2 — PMD failed to run

## Rules

- **Threshold is configurable.** Some teams accept 15; tighter teams set 8. Default 10 is the conventional middle
- **Don't analyze test classes.** They legitimately have many setup branches
- **PMD-driven for Apex.** Don't reimplement CC counting — PMD's tested implementation is the right call
- **Heuristic for LWC.** Without an AST parser available, the regex-based count is approximate. Flag the count alongside "approx" so the user knows
- **No auto-refactor.** This is a report; the user picks what to refactor

## Consumers

- `/argo:code-review` rolls hotspots into the LWC/Apex sections
- `@architect` consults complexity before approving large additions to existing methods
