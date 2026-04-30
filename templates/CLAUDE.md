# {{project.name}} — AI Workflow

This project uses the **`sf-dev-kit`** Claude Code plugin for its Salesforce AI workflow (agents, skills, hooks, standards docs). The workflow is project-agnostic and driven by `.claude/sf-project.json`.

> **Project-specific context** — including project name, object model, message channels, domain glossary, and unique constraints — lives in `docs/project-context.md`. Read that file for the *what* of this project; this file describes the *how* of the workflow itself.

---

## Project Config

The single source of truth for project-specific values is **`.claude/sf-project.json`**. It defines:

- `project.name` / `project.description` — display name
- `naming.lwc.prefix` / `naming.lwc.excludePrefixes` — LWC naming convention (empty prefix means no convention)
- `naming.apex.*` — class-name suffix conventions for controllers, services, batchables, schedulables, queueables, trigger handlers, and tests
- `platform.apiVersion` — API version for all new metadata
- `platform.defaultTargetOrg` — Salesforce CLI org alias for deploys, validations, and test runs
- `platform.lwcTargets` — LWC `<targets>` for `.js-meta.xml`
- `platform.sharingDefault` — default sharing model for new Apex classes
- `paths.*` — source and documentation paths (LWC source/docs, Apex source/docs, pattern docs, project context, standards docs)
- `quality.codeCoverageTarget` — Apex test coverage threshold
- `quality.lintCommand` / `quality.unitTestCommand` — npm scripts run by the workflow

Agents and skills read this file at task start. Update the config rather than hardcoding values in the workflow files.

To re-bootstrap or update the project config, run **`/sf-dev-kit:sf-init`**.

---

## Development Standards

- **API version**: use `platform.apiVersion` from config for all new metadata
- **Sharing**: use `platform.sharingDefault` (typically `with sharing`); document any deviation in code
- **Data access**: prefer `@wire` over imperative Apex for read-only data
- **Cross-component comms**: use Lightning Message Service (channels are listed in `docs/project-context.md`)
- **Code style**: Prettier + ESLint, enforced via the plugin's `lint-lwc.sh` `PostToolUse` hook on edited LWC JS files

## Creating a New LWC

1. Scaffold JS + HTML + CSS + XML meta in `{paths.lwcSource}/{prefix}{Name}/`. The prefix and source path come from `.claude/sf-project.json`
2. If the component needs user/org context, subscribe to one of the project's LMS channels (see `docs/project-context.md`)
3. If it needs Apex data, create or reuse a controller in `{paths.apexSource}`
4. Add `@api` properties for any Experience Builder-configurable values
5. Create Jest test in `__tests__/{componentName}.test.js`
6. Add doc file in `{paths.lwcDocs}/{componentName}.md` and update the index README in the same directory
7. Run `{quality.lintCommand} && {quality.unitTestCommand}` before committing

## Creating a New Apex Class

1. Create `.cls` + `.cls-meta.xml` in `{paths.apexSource}`
2. Use `@AuraEnabled(cacheable=true)` for read-only LWC methods
3. Create test class `{ClassName}{naming.apex.testSuffix}.cls` — target `quality.codeCoverageTarget`% coverage
4. Add doc file in `{paths.apexDocs}/{ClassName}.md` and update the index README
5. Run `{quality.lintCommand}` before committing

## Testing

- **LWC**: run `{quality.unitTestCommand}` (typically `npm run test:unit`); watch and coverage variants exist if package.json defines them
- **Apex**: `sf apex run test --target-org {platform.defaultTargetOrg}` or use the `/sf-dev-kit:test-coverage` skill
- **Pre-commit hook**: Prettier → ESLint → Jest on modified LWC files (with `--passWithNoTests`)

## Deployment

- **Deploy**: `sf project deploy start --target-org {platform.defaultTargetOrg}`, or use the `/sf-dev-kit:deploy` skill
- **Validate only**: append `--dry-run`
- **Excluded from deploy** (`.forceignore`): test directories, `node_modules/`, IDE config, `package.xml`

## Documentation

- LWC docs: `{paths.lwcDocs}/{componentName}.md` | index: `{paths.lwcDocs}/README.md`
- Apex docs: `{paths.apexDocs}/{ClassName}.md` | index: `{paths.apexDocs}/README.md`
- Full root index: `docs/README.md`

---

## Workflow Files (provided by `sf-dev-kit` plugin)

### Subagents (11 specialists)

| Agent | Role |
|-------|------|
| `@architect` | Read-only design + plan. Hand-off coordinator |
| `@data-architect` | Data model, sharing, LDV, migrations |
| `@integration-architect` | Callouts, Named Credentials, Platform Events, CDC, MCP Bridge, Trusted Agent Identity, Agent Fabric |
| `@apex-dev` | Apex implementation |
| `@lwc-dev` | LWC implementation |
| `@react-dev` | React-on-Salesforce implementation (when `platform.frontend` includes react) |
| `@agent-dev` | Agentforce agent authoring (topics, sub-agents, actions, eval suites) |
| `@qa` | Tests + severity-graded code review |
| `@e2e-tester` | UTAM / Playwright end-to-end tests |
| `@security-reviewer` | OWASP-for-SF deep review |
| `@trust-reviewer` | OWASP-for-LLM on agents (prompt injection, jailbreak, grounding leakage) |

**Typical flow**: `@architect` plans → hands off to specialists → builders work in parallel → `@qa` reviews → `@e2e-tester` covers journeys → `@security-reviewer` + `@trust-reviewer` before prod.

### Skills (invoke as `/sf-dev-kit:<name>`)

**Setup**: `sf-init`, `onboard`, `pattern-pack`, `mcp-setup`
**Org awareness**: `org-explore`, `org-diff`, `flow-audit`, `permset-audit`, `field-impact`, `agent-discover`
**Architecture**: `erd`, `sequence-diagram`, `adr`, `flow-vs-apex`, `agent-vs-flow-vs-apex`, `lwc-vs-react`, `mcp-tool-vs-rest`, `before-vs-after-trigger`, `queueable-vs-batch`
**Agent dev**: `agent-spec`, `agent-test`, `agent-eval-trend`, `agent-deploy`, `mcp-bridge`, `slack-agent`, `agent-exchange-list`
**React**: `react-init`
**Testing**: `test-plan`, `test-data`, `test-coverage` (apex/agent modes), `coverage-trend`, `flaky-test-finder`
**Code review & static analysis**: `code-review`, `security-scan`, `fls-audit`, `sharing-review`, `soql-analyzer`, `limit-usage`, `perf-review`, `dead-code`, `complexity`, `dependency-graph`
**Trust & governance**: `trust-layer-audit`, `trust-eval`, `gateway-config`
**Deployment**: `deploy`, `diff-deploy`, `quick-deploy`, `scratch-org`, `package-version`, `destructive-changes`, `devops-natural`
**Docs & release**: `generate-docs`, `release-notes`, `pr-prepare`, `notify`

(See `${CLAUDE_PLUGIN_ROOT}/README.md` or run `/sf-dev-kit:pattern-pack list` for the full inventory.)

### Standards & Patterns (in this project's `docs/`)

- **`docs/patterns/salesforce-patterns.md`** — Generic platform patterns SF-1..SF-20
- **`docs/patterns/project-patterns.md`** — Project-specific patterns
- **`docs/apex-standards.md`** — Apex governor limits, security, SOQL/DML, async, naming
- **`docs/lwc-standards.md`** — LWC CSS, JavaScript, accessibility
- **`docs/react-standards.md`** — React-on-Salesforce specifics (when `platform.frontend` includes react)
- **`docs/quality-checklist.md`** — Unified pre-flight checklist (with Agent + Trust Layer + AI Gateway sections)
- **`docs/project-context.md`** — Object model, channels, glossary, project-specific constraints

All agents read both pattern docs and the relevant standards docs before writing code.

### Pattern Packs (opt-in, install with `/sf-dev-kit:pattern-pack add <name>`)

- **`agentforce` v1.0** — AGT-1..7 for projects shipping Agentforce agents
- **`react` v1.0** — RX-1..6 when `platform.frontend` includes react
- `platform-events` v1.0 — PE-1..5
- `change-data-capture` v1.0 — CDC-1..5 (paired with platform-events for the event-bus surface)
- `external-objects` v1.0 — EXT-1..5 (Salesforce Connect: OData / Cross-Org / Custom Apex)
- `big-objects` v1.0 — BIG-1..5 (append-only archival + Async SOQL)
- `field-service` v1.0 — FS-1..5 (Work Orders, scheduling, mobile offline)
- `industries` v1.0 — IND-1..6 (OmniStudio: OmniScripts, FlexCards, IPs, DataRaptors, EPC, Apex extensions)
- `cms` v1.0 — CMS-1..5 (content types, channels, multi-locale, headless delivery)
- `data-cloud` v1.0 — DC-1..5 (DLO/DMO, identity resolution, calculated insights, activations)
- ~~`einstein-agentforce`~~ — deprecated redirect, superseded by `agentforce` (kept for back-compat)

### Per-environment overrides

`.claude/sf-project.<env>.json` deep-merges over the base config when any skill is invoked with `--env <name>`. Common pattern: `prod` overrides `defaultTargetOrg`, raises `codeCoverageTarget` and `agentEvalThreshold`, narrows `mcp.toolsets` to read-only, configures `notifications.webhooks` for Slack/Teams alerts.

### Security model

The plugin enforces four hard invariants (see `${CLAUDE_PLUGIN_ROOT}/docs/security-model.md`):

1. No contact with orgs classified in `security.prodOrgAliases`
2. Metadata-only SOQL by default; customer-data queries require per-call user consent
3. Anonymous Apex disabled by default
4. Overrides are runtime-only — no persistent "always allow"

`/sf-dev-kit:sf-init` requires every non-sandbox alias to be classified before it writes config. Three skills (`/trust-eval`, `/permset-audit`, `/agent-test`) prompt for consent on every run because they fundamentally need customer data.

### MCP Toolsets (Headless 360)

When `mcp.toolsets` is configured (run `/sf-dev-kit:mcp-setup`), the workflow routes through Salesforce's official `@salesforce/mcp` server. Toolsets: `metadata, data, testing, lwc, code-analysis, devops, aura`. The plugin's `hooks/lib/mcp.sh` falls back to direct `sf` CLI when the MCP server isn't available — every skill works either way.
