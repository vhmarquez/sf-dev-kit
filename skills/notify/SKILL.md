---
name: notify
description: Post a structured notification to a configured Slack or Microsoft Teams webhook. Used by deploy / coverage / security skills (or CI pipelines) to broadcast results without hardcoding webhook URLs in scripts. Webhook URLs come from `.claude/sf-project.json` (or env override).
data-access: none
---

You are posting a notification to a team chat webhook. The webhook URL lives in the project config under `notifications.webhooks`; this skill never accepts a URL as an argument (so it's safe in shell history).

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
SLACK_URL="$(sf_config_get '.notifications.webhooks.slack // empty' "$ENV")"
TEAMS_URL="$(sf_config_get '.notifications.webhooks.teams // empty' "$ENV")"
```

## Config Schema (in `sf-project.json`)

```json
{
  "notifications": {
    "webhooks": {
      "slack": "https://hooks.slack.com/services/T.../B.../X...",
      "teams": "https://outlook.office.com/webhook/..."
    },
    "channels": {
      "deploy": ["slack"],
      "coverage": ["slack", "teams"],
      "security": ["slack"],
      "release": ["slack", "teams"]
    }
  }
}
```

The `channels` map says which event types go to which platforms. If empty, all configured platforms receive every event.

`/sf-dev-kit:sf-init` (Phase 1) does not prompt for these by default — they're sensitive. Recommend adding to a per-env override file (`.claude/sf-project.prod.json`) so dev/QA don't post to the team channel during testing.

## Input

`$ARGUMENTS`: required.
- `<event-type> <payload-json>` — e.g., `deploy '{"status":"Succeeded","org":"Prod","componentCount":12,"deployId":"0Af..."}'`
- `--channel slack|teams|all` — override the configured channel routing
- `--dry-run` — print the message that would be sent without posting

## Event types and rendering

| Event | Slack rendering | Teams rendering |
|-------|-----------------|-----------------|
| `deploy` | `:rocket: *Deploy <status>* to <org> — <componentCount> components — <deployId>` + actions block linking to deploy log | Adaptive Card with the same fields |
| `coverage` | `:bar_chart: *Coverage <delta>* — overall <percent>% — <regressions count> classes regressed` | Adaptive Card |
| `security` | `:rotating_light: *Security scan* — <criticalCount> critical, <warningCount> warning` | Adaptive Card |
| `release` | `:package: *<version> released* — <highlightCount> features, <fixCount> fixes — <releaseNotesUrl>` | Adaptive Card |
| `custom` | `<text>` (raw) | `<text>` |

## Steps

### 1. Validate inputs
- Event type must be one of the supported list
- Payload must be valid JSON

### 2. Render messages

For Slack (Block Kit):
```json
{
  "blocks": [
    { "type": "section", "text": { "type": "mrkdwn", "text": "<rendered text>" } },
    { "type": "context", "elements": [{ "type": "mrkdwn", "text": "<project.name> · <org>" }] }
  ]
}
```

For Teams (Adaptive Card):
```json
{
  "type": "message",
  "attachments": [
    {
      "contentType": "application/vnd.microsoft.card.adaptive",
      "content": { "type": "AdaptiveCard", "body": [...], "version": "1.4" }
    }
  ]
}
```

### 3. Post

```bash
curl -fsS -X POST -H 'Content-Type: application/json' --data "$BODY" "$WEBHOOK_URL"
```

Capture HTTP status. Slack returns `ok` (200); Teams returns `1` (200).

### 4. Output

Default:
```
[notify] Posted deploy notification to slack (HTTP 200)
[notify] Posted deploy notification to teams (HTTP 200)
```

`--dry-run`:
```
[notify] Would POST to slack: <URL truncated>
{"blocks": [...]}
```

CI mode: emit `{"posted": ["slack", "teams"], "errors": []}`.

## Exit codes
- 0 — all configured channels accepted the post (or `--dry-run`)
- 1 — at least one channel rejected (HTTP 4xx/5xx)
- 2 — invocation error (no webhook configured, invalid event type)

## Rules

- **Never log webhook URLs.** They're effectively credentials. Truncate when echoing in dry-run
- **Never accept a webhook URL via $ARGUMENTS.** Force users to put it in config
- **Don't fail loudly in CI.** A failed notification shouldn't break a deploy. Exit 1 with a message; the caller decides whether to retry
- **Truncate long payloads.** Slack/Teams cap message size; if a release note is >4 KB, truncate with a "see full notes at <URL>" footer
- **Sensitive content scrub.** Never include test data, customer PII, or auth tokens in the message. The skill blocks if the rendered text contains anything matching common token patterns

## Consumers

- CI deploy pipeline: `/sf-dev-kit:notify deploy "$DEPLOY_RESULT_JSON"`
- `/sf-dev-kit:test-coverage` posts a `coverage` event when run with `--notify`
- `/sf-dev-kit:security-scan` posts a `security` event when run with `--notify`
- Release process: `/sf-dev-kit:release-notes` + `/sf-dev-kit:notify release ...`
