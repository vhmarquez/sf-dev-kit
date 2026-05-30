---
name: slack-agent
description: Scaffold a Slack-native Salesforce agent end-to-end via the Slack Agent Kit. Generates the agent's botDefinition, Slack manifest, channel-bot Apex bridge, and a starter Block Kit response template. Aim is "CLI to live agent in 10 minutes".
data-access: none
---

You are scaffolding a **Slack-native** agent — an Agentforce agent that lives in Slack as both a bot user and a workflow surface. This wraps Salesforce's **Slack Agent Kit** with argo's project conventions.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
SLACK_WEBHOOK="$(sf_config_get '.notifications.webhooks.slack // empty' "$ENV")"
AGENT_DIR="$(sf_config_get '.paths.agentDefinitions // \"force-app/main/default/botDefinitions\"' "$ENV")"
```

## Input

`$ARGUMENTS`:
- `<agent-name>` — required; the agent's developer name
- `--slack-app-id <id>` — existing Slack app to reuse (skip new-app creation)
- `--workspace <id>` — Slack workspace where the agent will be installed
- `--connect-data-cloud` — also wire Data Cloud for richer grounding (optional)
- `--ci` — non-interactive; expects all flags

## Steps

### 1. Pre-flight

- Confirm Slack CLI authenticated: `slack auth list`
- Confirm Salesforce CLI authenticated to `$ORG`: `sf_cli_alias_exists "$ORG"`
- Confirm the project ships a base agent at `<AGENT_DIR>/<agent-name>/` (run `/argo:agent-spec <agent-name>` first if not)

### 2. Generate the Slack manifest

Output to `slack/manifest.<agent-name>.json`:
```json
{
  "display_information": {
    "name": "<agent-name>",
    "description": "<agent description from spec>"
  },
  "features": {
    "bot_user": {
      "display_name": "<agent-name>",
      "always_online": true
    },
    "shortcuts": [],
    "slash_commands": [
      { "command": "/<agent-name>", "description": "Talk to the <agent-name> agent", "url": "https://<your-tunnel>/slack/events" }
    ]
  },
  "oauth_config": {
    "scopes": {
      "bot": ["app_mentions:read", "channels:history", "chat:write", "commands", "im:history", "im:read", "users:read"]
    }
  },
  "settings": {
    "event_subscriptions": {
      "request_url": "https://<your-tunnel>/slack/events",
      "bot_events": ["app_mention", "message.im"]
    },
    "interactivity": { "is_enabled": true, "request_url": "https://<your-tunnel>/slack/events" }
  }
}
```

### 3. Generate the Slack ↔ Salesforce bridge

Two layers:
- **Slack-side** (Bolt-on-Cloudflare or Heroku): `slack/<agent-name>/app.ts` — receives Slack events, forwards to the org via the Connect REST API's agent endpoint, returns the response as Block Kit
- **Salesforce-side**: `<AGENT_DIR>/<agent-name>/topics/slack_handoff.topic-meta.xml` — a topic that receives the user-message and returns a structured response payload the bridge converts to Block Kit

```ts
// slack/<agent-name>/app.ts
import { App } from '@slack/bolt';
import { invokeAgent } from '@salesforce/agentforce-slack';

const app = new App({ token: process.env.SLACK_BOT_TOKEN, signingSecret: process.env.SLACK_SIGNING_SECRET });

app.event('app_mention', async ({ event, say }) => {
  const response = await invokeAgent({
    agent: '<agent-name>',
    user: event.user,
    message: event.text,
    org: process.env.SF_ORG_ALIAS!,
  });
  await say({ blocks: response.blocks, text: response.fallbackText });
});

app.event('message', async ({ event, say }) => {
  if (event.channel_type === 'im') {
    const response = await invokeAgent({ agent: '<agent-name>', user: event.user, message: event.text, org: process.env.SF_ORG_ALIAS! });
    await say({ blocks: response.blocks, text: response.fallbackText });
  }
});

(async () => { await app.start(process.env.PORT || 3000); })();
```

### 4. Block Kit response template helpers

Generate `slack/<agent-name>/blocks.ts` with reusable Block Kit helpers:

```ts
import { KnownBlock, Card, Alert, Carousel, DataTable, Chart } from '@salesforce/agentforce-slack/blocks';

export function orderCard(order: OrderResponse): KnownBlock[] {
  return Card({
    title: order.name,
    fields: [
      { label: 'Status', value: order.status },
      { label: 'Total', value: order.totalFormatted },
    ],
    actions: [
      { id: 'view',   text: 'View',   value: order.id },
      { id: 'cancel', text: 'Cancel', value: order.id, style: 'danger' },
    ],
  });
}

export function notFoundAlert(query: string): KnownBlock[] {
  return Alert({ kind: 'warning', text: `No order matched "${query}".` });
}
```

The `@salesforce/agentforce-slack/blocks` builders are the Block Kit additions (Card, Alert, Carousel, Data Table, Chart).

### 5. Wire deploys + secrets

- Add the Slack app id and signing secret to a secret manager (NOT in `notifications.webhooks` config — those are unauthenticated webhook URLs, not signing secrets)
- Generate `.env.example` for the Slack-side bridge with placeholder env-var names; the user fills in their tunnel
- Print the Slack CLI install command:
  ```
  slack manifest validate --file slack/manifest.<agent-name>.json
  slack app create --manifest-file slack/manifest.<agent-name>.json --workspace <workspace-id>
  ```

### 6. Smoke test

```bash
# Locally (with ngrok or Cloudflare tunnel pointing to the bolt app)
slack run

# Then in Slack:
@<agent-name> hello
```

If the agent has been deployed via `/argo:agent-deploy`, the org responds; the bridge converts to Block Kit; the user sees the formatted card.

## Output

```
# Slack Agent Scaffolded: order_helper

Files created:
  slack/manifest.order_helper.json
  slack/order_helper/app.ts
  slack/order_helper/blocks.ts
  slack/order_helper/.env.example
  slack/order_helper/package.json
  <AGENT_DIR>/order_helper/topics/slack_handoff.topic-meta.xml

Required secrets (not committed; add via your secret manager):
  SLACK_BOT_TOKEN
  SLACK_SIGNING_SECRET
  SF_ORG_ALIAS  (set to: DevVM)

## Next steps
1. Create the Slack app from the manifest:
   slack manifest validate --file slack/manifest.order_helper.json
   slack app create --manifest-file slack/manifest.order_helper.json
2. Tunnel a local server: ngrok http 3000  (or Cloudflare tunnel)
3. Update slack/manifest.order_helper.json `request_url` to the tunnel URL
4. Run the bridge locally: cd slack/order_helper && npm install && npm run dev
5. In Slack: @order_helper hello → should respond with the agent
6. Once verified, deploy the bridge to a permanent host (Cloudflare Worker, Heroku, etc.)
```

## Exit codes
- 0 — scaffolding done
- 1 — pre-flight failed (auth, missing base agent)
- 2 — invocation error

## Rules

- **The base agent must exist first.** Run `/argo:agent-spec` and `/argo:agent-deploy` before this skill — Slack is a delivery surface, not the source of truth
- **Block Kit responses are the agent's structured output**, not free text. The agent's `slack_handoff` topic returns a typed payload; the bridge maps to Block Kit. Free text is the fallback for unstructured cases
- **Secrets are never written to the project.** `.env.example` documents required vars; users add to their secret manager
- **Refuse to scaffold without a deployed base agent.** Slack-only agents don't gate via `/argo:agent-test` and are a Trust Layer escape route — the workflow assumes the org-side agent exists
- **Per-workspace deploys.** A multi-workspace install needs a per-workspace manifest; this skill scaffolds for one workspace at a time

## Consumers

- Internal collab: an agent that anyone in the workspace can `@mention`
- Deploy bots: `@deploy-bot push the order changes to QA` → the bridge invokes the org-side agent action
- Onboarding helpers: a `@helper` bot that answers FAQs grounded in `docs/project-context.md`
