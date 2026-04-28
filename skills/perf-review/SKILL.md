---
name: perf-review
description: Static performance review of Lightning Web Components — bundle size, render-blocking imports, @wire waterfall, large templates, missing virtualization, unnecessary re-renders. Reports per-component findings and an aggregate summary.
---

You are performing a **performance review** of LWCs. The review is static (file-content analysis); it doesn't run a browser. Findings are heuristic but actionable.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
LWC_SRC="$(sf_config_get '.paths.lwcSource' "$ENV")"
PREFIX="$(sf_config_get '.naming.lwc.prefix' "$ENV")"
EXCLUDES_JSON="$(sf_config_get '.naming.lwc.excludePrefixes' "$ENV")"
```

## Input

`$ARGUMENTS`:
- (empty) — review every in-scope component
- `<lwc-name>` — single component
- `--ci` / `--format json|sarif` / `--out <path>`

## Per-component checks

### 1. Bundle size

```bash
js_size=$(stat -c %s "${LWC_SRC}/${name}/${name}.js" 2>/dev/null || stat -f %z ...)
html_size=...
css_size=...
total=$((js_size + html_size + css_size))
```

| Threshold | Severity | Rule ID |
|-----------|----------|---------|
| Single JS > 30 KB | warning | `PERF-LARGE-JS` |
| Single HTML > 20 KB | warning | `PERF-LARGE-HTML` |
| Bundle (JS+HTML+CSS) > 75 KB | warning | `PERF-LARGE-BUNDLE` |

For oversized bundles, suggest SF-20 (Lazy-Loaded Sub-component) or SF-19 (Virtualized List).

### 2. `@wire` waterfall

Count `@wire` decorators in the JS file. If > 4 wires, flag:
- `PERF-MANY-WIRES` (warning) — too many wires render-block the first paint
- Suggested: combine into a single Apex aggregator, or move secondary wires behind `lwc:if` after primary wires resolve

### 3. Render-blocking imports

Count top-level `import` statements at the file head. The LWC compiler tree-shakes, but very large bundles signal copy-paste imports or unused libraries:
- `PERF-MANY-IMPORTS` (note) — > 30 imports

### 4. Static resource loading

- `PERF-RESOURCE-IN-CONNECTED` (warning) — `loadScript`/`loadStyle` called in `connectedCallback` instead of after a user action; static resources are network-fetched and block first paint

### 5. Large lists without virtualization

Search the HTML for `template lwc:for|for:each` blocks. If the JS source bound to the iterable shows source-code patterns suggesting > 500 rows (e.g., a `@wire` to a non-paginated Apex method, or a `pageSize` not set):
- `PERF-LARGE-LIST-NO-VIRTUAL` (warning) — recommend SF-1 paginated datatable or SF-19 virtualized list

### 6. Unnecessary re-renders

Heuristics for re-render risk:
- `PERF-WIRE-DEEP-OBJECT` (note) — `@wire` resolves into a property used directly in the template (object identity changes invalidate the entire subtree). Prefer a getter that returns a stable shape
- `PERF-TRACK-PRIMITIVE` (warning) — `@track` on a primitive (number/string/bool); `@track` only matters for object/array reactivity
- `PERF-RENDER-CALLBACK-STATE` (error) — `renderedCallback` mutates `@track` state without a `if (this._initialized) return;` guard → infinite render loop risk

### 7. Heavy library detection

```bash
grep -E "loadScript.*((chart\\.?js|moment\\.?js|lodash|d3|three|monaco|ace|tinymce))" ...
```
- `PERF-HEAVY-LIB-EAGER` (warning) — recommend SF-20 lazy-loading

## Output

Default Markdown:
```
# Performance Review: <project.name>

Components scanned: 18 (in-scope by `naming.lwc.prefix`)
Run at: 2026-04-28T14:00:00Z

## Findings

### Critical
- `PERF-RENDER-CALLBACK-STATE` — `acmeOrderForm.renderedCallback` mutates `selectedItem` without a guard

### High
- `PERF-LARGE-LIST-NO-VIRTUAL` — `acmeUserList` renders an unbounded list. Use SF-1 pagination or SF-19 virtualization
- `PERF-MANY-WIRES` — `acmeDashboard` has 7 @wire decorators; combine or sequence with lwc:if

### Medium
- `PERF-LARGE-BUNDLE` — `acmeReportBuilder` is 92 KB total (JS 60 + HTML 22 + CSS 10). Consider lazy-loading SF-20.
- `PERF-HEAVY-LIB-EAGER` — `acmeReportBuilder` loads chart.js in connectedCallback
- ...

## Bundle size summary

| Component | JS | HTML | CSS | Total |
|-----------|-----|------|-----|-------|
| acmeOrderForm | 18 KB | 6 KB | 2 KB | 26 KB |
| acmeReportBuilder | 60 KB | 22 KB | 10 KB | 92 KB ⚠️ |
| ...
```

CI: SARIF per finding; bundle-size table emitted as a sidecar JSON if `--format sarif`.

## Exit codes
- 0 — no error/warning findings
- 1 — any finding
- 2 — config error

## Rules

- **No browser, no benchmarks.** This is static. The user runs Chrome DevTools / Lightning Inspector for runtime profiling
- **Honor `naming.lwc.excludePrefixes`.** Layout-only or framework wrapper components shouldn't be flagged for size
- **Cross-link to patterns.** Every finding mentions the relevant SF-N or PRJ-N
- **Don't flag tests.** Skip `__tests__/`

## Consumers

- `/sf-dev-kit:code-review` rolls per-component findings into the LWC sections of the review report
- `@architect` references the bundle-size summary when planning new components
