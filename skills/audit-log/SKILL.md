---
name: audit-log
description: Review argo's local decision/audit log for the current project — every org-access grant, denial, and consent prompt the security layer recorded. Summarizes by decision and org, lists recent entries, supports filters and CI JSON output. Read-only — reads a local file, never contacts an org.
data-access: none
---

You are reviewing the **decision log** (audit trail) that argo's security layer writes for this project. Every org-access decision is appended as one JSON line: grants (`allow-once`), hard refusals (`refused` — e.g. prod blocks), and consent prompts (`consent_required`). This skill **only reads** that local file — it makes no org contact and writes nothing.

Line schema: `{ts, decision, reason, skill, action, target, org}`. Note one quirk in the current format: **grants** (`allow-once`) encode the org inside `target` as `Object@alias` with `org` empty, while **denials/prompts** populate `target` and `org` separately — account for both when grouping by org (match `org` OR a `@alias` suffix in `target`).

## Locate the log

The path is owned by the security library — source it so the project's filename and `CLAUDE_PLUGIN_DATA` resolution stay in lockstep with what the hooks write:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/security.sh"
LOG="$SEC_CONSENT_LOG"
command -v jq >/dev/null || { echo "[audit-log] jq is required" >&2; exit 2; }
```

If `$LOG` does not exist, no org-access decisions have been recorded for this project yet — report that and stop (exit 0). The log lives **outside the repo** under `${CLAUDE_PLUGIN_DATA}/argo/consent-log/` (it is never written into the project).

## Input

`$ARGUMENTS`:
- (empty) — summary + the 20 most recent entries
- `--denials` — only `refused` events (blocked prod / hard refusals)
- `--grants` — only `allow-once` (authorized) events
- `--prompts` — only `consent_required` events
- `--org <alias>` — only entries against that org
- `--skill <name>` — only entries from that skill
- `--since <ISO-date>` — only entries at/after the date (e.g. `2026-05-01`)
- `--last <N>` — show N most recent (default 20); `--all` shows everything
- `--ci` — machine output; with `--format json` (default in CI) emit the filtered array plus a summary object

## Steps

### 1. Summary (always computed over the full log)

```bash
jq -s '{
  total: length,
  byDecision: (reduce .[] as $e ({}; .[$e.decision] += 1)),
  prodBlockAttempts: ([.[] | select(.reason == "PROD_ORG_BLOCKED")] | length),
  orgs: ([.[].org] | map(select(. != "")) | unique),
  first: (.[0].ts // null),
  last:  (.[-1].ts // null)
}' "$LOG"
```

### 2. Filtered listing

Build a jq `select(...)` from the flags (decision / org / skill / since), then take the most recent N (`--all` ⇒ omit the `tail`):

```bash
jq -c 'select(
    (true)                                   # base
    # and (.decision == "refused")           # --denials  ("allow-once" / "consent_required" for --grants / --prompts)
    # and (.org == "<alias>")                # --org
    # and (.skill == "<name>")               # --skill
    # and (.ts >= "<ISO>")                   # --since
  )' "$LOG" | tail -n "${N:-20}"
```

Render each line as a readable row: `ts · decision · reason · skill · action · target@org`.

## Output

Default (Markdown):

```
# argo decision log — <project>

Recorded: 142 decisions  (2026-05-01 → 2026-05-29)
  allow-once        88
  consent_required  41
  refused           13   ⚠️ incl. 9 prod-block attempts
Orgs touched: DevVM, UAT-Sandbox

## Recent (last 20)
2026-05-29T21:03Z  refused           PROD_ORG_BLOCKED   trust-eval     any   @ProdProd
2026-05-29T20:55Z  allow-once        —                  permset-audit  soql  PermissionSetAssignment@DevVM
…
```

CI mode (`--ci --format json`): a single JSON object to stdout, nothing else —

```json
{
  "summary": { "total": 142, "byDecision": { "allow-once": 88, "consent_required": 41, "refused": 13 }, "prodBlockAttempts": 9, "orgs": ["DevVM", "UAT-Sandbox"] },
  "entries": [ { "ts": "…", "decision": "refused", "reason": "PROD_ORG_BLOCKED", "skill": "trust-eval", "action": "any", "target": "", "org": "ProdProd" } ]
}
```

## Exit codes

- 0 — log reviewed (or none recorded yet)
- 2 — `jq` missing, or the log exists but is unreadable

## Rules

- **Read-only.** Never modify, rotate, or delete the log; never contact an org. `data-access: none`.
- **Surface prod-block attempts.** Highlight `reason == PROD_ORG_BLOCKED` — repeated entries can signal a misconfigured alias or a skill targeting prod.
- **Don't relocate the log.** This skill reviews the canonical `${CLAUDE_PLUGIN_DATA}` location; it must not copy the log into the project (committing org aliases + an access trail is a leak risk).
- **Clean CI output.** In `--ci` mode emit only JSON to stdout so it pipes into dashboards/notifications.
