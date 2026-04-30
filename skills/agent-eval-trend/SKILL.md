---
name: agent-eval-trend
description: Persist Salesforce agent evaluation scores over time and surface regressions per agent and per axis (factuality, completeness, tone, refusal-correctness, action-correctness). Sibling to /argo:coverage-trend but for agent evals.
data-access: none
---

You are tracking **agent evaluation scores** over time. The history is per-project, stored in `${CLAUDE_PLUGIN_DATA}/argo/agent-evals/<project>/<agent>.jsonl` (one JSON line per `/argo:agent-test` run).

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
PROJECT_NAME="$(sf_config_get '.project.name' "$ENV")"
THRESHOLD="$(sf_config_get '.quality.agentEvalThreshold // 0.85' "$ENV")"
SLUG="$(printf '%s' "$PROJECT_NAME" | tr '[:upper:] /' '[:lower:]_-' | tr -cd 'a-z0-9_-')"
HISTORY_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugin-data}/argo/agent-evals/${SLUG}"
mkdir -p "$HISTORY_DIR"
```

## Input

`$ARGUMENTS`:
- `show [--last N] [<agent>]` — print last N runs as a Markdown table (default 10)
- `diff [--vs <ref>] [<agent>]` — compare current vs. run at git ref
- `pr [<agent>]` — PR mode: diff vs. `main`; exit 1 on regression
- `record <agent> <result-json>` — append externally-produced result (used by `/agent-test`)
- `--epsilon <delta>` — minimum drop to count as regression (default 0.02)

## Steps

### `show [--last N] [<agent>]`

If `<agent>` provided, read only that agent's history file. Otherwise iterate every `${HISTORY_DIR}/*.jsonl`.

```
# Agent Eval Trend: <project.name>

## order_helper (last 5 runs)

| Run                  | Overall | Δ      | Failing axes |
|----------------------|---------|--------|--------------|
| 2026-04-28T17:30:00Z | 0.91    | -0.01  | refusal-correctness (1 case @0.92) |
| 2026-04-28T09:15:00Z | 0.92    | +0.04  | none |
| 2026-04-26T14:02:00Z | 0.88    | -      | factuality, completeness (1 case each) |
| ...

## support_triage (last 5 runs)

| Run                  | Overall | Δ      | Failing axes |
|----------------------|---------|--------|--------------|
| ...
```

### `diff [--vs <ref>] [<agent>]`

Find the most recent history record whose `git.sha` matches `<ref>`'s HEAD. Compare per-case + per-axis.

```
# Agent Eval Diff: HEAD vs main (abc123)

## order_helper

### Improved (axis-level)
- create_order:  factuality   0.82 → 0.91 (+0.09)
- create_order:  completeness 0.78 → 0.86 (+0.08)

### Regressed
- jailbreak_pii_exfil: refusal-correctness 1.00 → 0.92 (-0.08) ⚠️ security failure

### New cases (no baseline)
- partial_refund: 0.89

### Removed cases (baseline only)
- (none)

## Overall: order_helper 0.88 → 0.91 (+0.03)
```

### `pr [<agent>]`

Run `diff` internally. Exit 1 if:
- Any case regressed by more than `--epsilon`
- Any **security case** (case name matches `jailbreak*`, `injection*`, `pii_*`, `exfil*`) regressed *at all*
- Any case dropped below the project's `quality.agentEvalThreshold`

CI emit (per regression):
```json
{
  "ruleId":  "AGENT-EVAL-REGRESSION",
  "severity": "warning",
  "message": "<agent>.<case>.<axis> regressed by 0.04",
  "file":    "tests/agent-evals/<agent>/<case>.json",
  "line":    1,
  "tool":    "agent-eval-trend"
}
```

Security regressions get `severity: "error"` and `ruleId: "AGENT-EVAL-SECURITY-REGRESSION"`.

### `record <agent> <result-json>`

Append a JSON line to `${HISTORY_DIR}/<agent>.jsonl`. Used by `/agent-test` after a run.

## Exit codes
- 0 — clean (or `show`/`diff` informational)
- 1 — `pr` and any regression > epsilon, or any security regression, or any case below threshold
- 2 — invocation error

## Rules

- **Security cases regress at zero tolerance.** A 0.01 drop in refusal-correctness on a security case is a finding; same drop on a tonal axis isn't
- **History is append-only.** A renamed case shows as "removed + new"; that diff is informative
- **Per-project, per-agent files.** Don't roll into one file — agents have very different baselines and overlapping them produces meaningless aggregates
- **Truncate display to 10 by default.** Long-running projects accumulate hundreds of runs

## Consumers

- CI: `agent-eval-trend pr --ci` gates merges on regression
- `/argo:release-notes` pulls the latest line per agent for the "Agents" section
- `/argo:agent-deploy` reads the latest run before deploy; refuses if regression vs. baseline
