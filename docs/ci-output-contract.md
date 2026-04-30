# CI Output Contract

This document defines the machine-readable output contract for argo skills that support CI integration. Skills that emit findings (e.g., `/code-review`, `/test-coverage`, `/security-scan`, `/dead-code`, `/complexity`, `/perf-review`, `/soql-analyzer`) honor this contract.

## Modes

A skill is in CI mode when invoked with `--ci`. CI mode disables interactive prompts and produces machine-readable output. Two output formats are supported:

| Format | Flag | Use case |
|--------|------|----------|
| JSON   | `--format json` (default in CI mode) | Pipeline scripts, ad-hoc tooling |
| SARIF  | `--format sarif`                     | GitHub Code Scanning, IDE plugins, security dashboards |

Plain text output is the default outside CI mode and is not contract-stable.

## Exit codes

| Code | Meaning |
|------|---------|
| 0    | No findings (or only `note` severity in strict mode disabled) |
| 1    | One or more findings of severity `warning` or `error` |
| 2    | The skill itself failed to run (config missing, CLI error, etc.) |

Skills that surface coverage or quality thresholds (e.g., `/test-coverage`, `/complexity`) treat threshold breaches as severity `error` for exit-code purposes.

## Internal finding shape

All emitting skills produce findings in a uniform internal JSON shape before format conversion:

```json
[
  {
    "ruleId":   "SF-5",
    "severity": "error",
    "message":  "SOQL query inside a for loop on line 42",
    "file":     "force-app/main/default/classes/MyController.cls",
    "line":     42,
    "column":   3,
    "endLine":  46,
    "ruleHelpUri": "https://github.com/vmarquez/argo/blob/main/templates/docs/patterns/salesforce-patterns.md#sf-5",
    "tool":     "code-review"
  }
]
```

Required: `ruleId`, `message`, `file`. Defaults: `severity=warning`, `line=1`, `column=1`. Other fields optional.

## SARIF emitter

`hooks/lib/sarif.sh` exposes `sarif_emit [tool-name] [tool-version]` which reads the internal findings array on stdin and writes SARIF 2.1.0 on stdout. Invoking skills source the lib and pipe through it:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/sarif.sh"
echo "$findings_json" | sarif_emit "argo/code-review" "1.1.0" > review.sarif
```

## SARIF severity mapping

| Internal | SARIF `level` |
|----------|---------------|
| `error`  | `error`       |
| `warning`| `warning`     |
| `note`   | `note`        |
| (other)  | `warning`     |

## Per-skill rule IDs

Each skill prefixes its rule IDs to keep them globally unique:

| Skill | Prefix | Examples |
|-------|--------|----------|
| `/code-review` | `SF-` and `PRJ-` (matches pattern doc IDs) | `SF-5`, `PRJ-1` |
| `/security-scan` | `SEC-` (PMD `apex.security` rules also passed through) | `SEC-FLS-MISSING` |
| `/fls-audit` | `FLS-` | `FLS-DML-NO-CHECK` |
| `/sharing-review` | `SHR-` | `SHR-WITHOUT-SHARING` |
| `/dead-code` | `DEAD-` | `DEAD-METHOD-UNUSED` |
| `/complexity` | `CPX-` | `CPX-METHOD-OVER-15` |
| `/soql-analyzer` | `SOQL-` | `SOQL-NON-SELECTIVE` |
| `/perf-review` | `PERF-` | `PERF-WIRE-WATERFALL` |
| `/test-coverage` | `COV-` | `COV-BELOW-TARGET` |

## Skill invocation pattern

A skill that supports CI mode advertises it in its `SKILL.md` "Input" section and parses these flags:

```
--ci                Enable CI mode (machine-readable output, exit codes per contract)
--format <fmt>      json (default) or sarif
--out <path>        Write to file instead of stdout
--fail-on <level>   error (default), warning, note — minimum severity that triggers exit 1
```

Outside CI mode, skills retain their existing human-readable Markdown output.
