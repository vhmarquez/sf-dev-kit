# Changelog

All notable changes to **sf-dev-kit**. Format follows [Keep a Changelog](https://keepachangelog.com/) and the project follows [SemVer](https://semver.org/).

---

## v3.0.0 — 2026-04-28

The Headless 360 release. v2.x → v3.0 brings the plugin in line with everything Salesforce announced at TDX 2026: native MCP routing via `@salesforce/mcp`, agents as a first-class deployable artifact, the new React framework, the Einstein Trust Layer + AI Gateway controls, AgentExchange listing prep, and the natural-language deploy surface.

Built across phases 13–19 (one branch + tag per phase: `v2.1.0`..`v2.6.0` → `v3.0.0`).

### Added — agents (4 new specialists, total now 11)

- **`@react-dev`** — React-on-Salesforce sibling to `@lwc-dev`. Authors components with `@salesforce/react/graphql`, SLDS via tokens, i18n hooks, LWC↔React interop
- **`@agent-dev`** — Agentforce author. Translates Agent Script YAML into AgentDefinition metadata; references AGT-1..7 patterns; enforces Trust Layer rules at design time
- **`@trust-reviewer`** — Read-only OWASP-for-LLM specialist. Maps findings to LLM01..LLM10; covers prompt-injection resistance, output validation, grounding-data leakage, jailbreak, excessive agency, supply-chain (MCP tools)

### Added — skills (17 new, total now 56)

**MCP layer**
- `/mcp-setup` — install/configure `@salesforce/mcp`; persist `mcp.toolsets` per env
- `/mcp-bridge` — wrap an Apex REST class as an MCP tool registered in the Agent Registry
- `/agent-discover` — Agentforce inventory (source vs org reconciliation)

**Agent dev**
- `/agent-spec` — wrap `sf agent generate agent-spec` with project context
- `/agent-test` — Testing Center eval runs (factuality, completeness, refusal-correctness, action-correctness)
- `/agent-eval-trend` — per-agent score history; PR-mode regression diff; security regressions zero-tolerance
- `/agent-deploy` — gated agent deploy (Trust Layer audit + eval + regression checks)

**Trust & governance**
- `/trust-layer-audit` — Einstein Trust Layer config audit (org-level + per-agent)
- `/trust-eval` — runtime drift via Custom Scoring Evals + Session Tracing sampling
- `/gateway-config` — generate/validate AI Gateway config (dev/qa/prod profiles)

**React parity**
- `/react-init` — scaffold a React component bundle

**DevOps & decisions**
- `/devops-natural` — natural-language deploy via DevOps Center MCP
- `/slack-agent` — scaffold Slack-native agent via Slack Agent Kit
- `/agent-exchange-list` — AgentExchange listing readiness (mandatory + recommended checks)
- `/agent-vs-flow-vs-apex` — extends `/flow-vs-apex` with Agent as first-class option
- `/lwc-vs-react` — frontend framework decision helper
- `/mcp-tool-vs-rest` — integration pattern decision helper

### Added — pattern packs

- **`agentforce` v1.0** — AGT-1..7 (topic boundaries, sub-agent decomposition, guardrails, MCP-tool actions, FLS-aware grounding, memory & state, escalation paths). Replaces the v0.1 `einstein-agentforce` stub
- **`react` v1.0** — RX-1..6 (platform GraphQL fetch, platform-aware auth, deployment, SLDS via React tokens, i18n, LWC↔React interop)

### Added — hooks

- **`lint-react.sh`** — PostToolUse Prettier + ESLint on `.tsx`/`.jsx` in `paths.reactSource`. Bails cleanly when `platform.frontend` doesn't include react

### Added — infrastructure

- `hooks/lib/mcp.sh` — MCP routing helpers (`mcp_prefer`, `mcp_run <toolset> <tool>`, `mcp_list_tools`)
- `templates/docs/react-standards.md` — React-on-Salesforce standards doc; copied by `/sf-init` when `platform.frontend` includes react
- `templates/gateway/{dev,qa,prod}.json` — AI Gateway config templates
- `templates/scratch/seed-agents.apex` — agent-data seeding script for scratch orgs
- `templates/packs/agentforce/` — full pack (README, patterns, checklist, manifest)
- `templates/packs/react/` — full pack (README, patterns, checklist, manifest)

### Changed — config schema

- `platform.frontend` — `"lwc"` (default), `"react"`, or `"both"`
- `naming.react.prefix` — optional PascalCase prefix
- `paths.reactSource` / `paths.reactDocs`
- `paths.agentDefinitions` (default `force-app/main/default/botDefinitions`)
- `quality.agentEvalThreshold` (default 0.85)
- `mcp.toolsets` + `mcp.allowNonGaTools`
- `platform.devHubAlias` (used by `/scratch-org` and `/package-version` already in v2.x; now documented)

### Changed — existing agents/skills

- **`@architect`** — `Files to Create` types now include AgentDefinition + React component + MCP bridge spec; Implementation Sequence includes `@agent-dev`; Hand-off section adds `@agent-dev`, `@trust-reviewer`, `@react-dev`; Agent vs LWC vs Flow vs Apex heuristic
- **`@integration-architect`** — Direction & Pattern matrix gains MCP Tool / Trusted Agent Identity / Agent Fabric / MCP Bridge rows; Authentication Design matrix gains agent-platform-managed-session, mobile Trusted Agent Identity, cross-vendor Agent Fabric rows
- **`/sf-init`** — auto-detects `sfdx-project.json` even more (now also `paths.reactSource`); prompts for `platform.frontend` and `mcp.toolsets`; copies `react-standards.md` only when react is in scope
- **`/test-coverage`** — gains `apex` and `agent` modes (legacy bare class name routes to `apex` mode)
- **`/scratch-org`** — runs `seed-agents.apex` in addition to `seed.apex` when `botDefinitions/` exists
- **`/org-explore`** — cache is now opt-in (`--cache`); MCP `data` toolset preferred when available; new `--mcp` / `--no-mcp` overrides
- **`templates/docs/quality-checklist.md`** — new Agent section (Trust Layer, Prompt safety, Topics & guardrails, Eval suite, AI Gateway)
- **`templates/CLAUDE.md`** — references the 11-agent surface and the MCP toolset story

### Deprecated

- `templates/packs/einstein-agentforce/` — superseded by `agentforce`. Pack directory retained for back-compat with installed projects; `agentforce` is the authoritative version. Will be removed in a future major

### Migration from v2.x

1. Pull v3: `/plugin marketplace update sf-dev-kit`
2. (Recommended) Install Salesforce's MCP server: `/sf-dev-kit:mcp-setup --profile dev`
3. (Recommended) Re-run `/sf-dev-kit:sf-init update` to add the new config keys (`mcp.toolsets`, `platform.frontend`, `quality.agentEvalThreshold`, `paths.agentDefinitions` if you ship agents)
4. If you ship agents:
   - Replace `einstein-agentforce` pack: `/sf-dev-kit:pattern-pack remove einstein-agentforce && /sf-dev-kit:pattern-pack add agentforce`
   - Run `/sf-dev-kit:agent-discover` to inventory existing agents
   - Run `/sf-dev-kit:trust-layer-audit` against any active agent
5. If you adopt React: `platform.frontend = "react"` (or `"both"`), then `/sf-dev-kit:sf-init` re-copies the standards docs
6. Existing v2 workflows continue to work; v3 features are additive and opt-in

### Branching & versioning policy (continued from v2)

v3 was built across 7 phase branches (`phase/13-mcp-integration` → `phase/19-v3-release`), each merged to `main` with `--no-ff`. Tags: `v2.1.0` (Phase 13), `v2.2.0` (Phase 14), …, `v2.6.0` (Phase 18), `v3.0.0` (Phase 19 + the v3 marker).

---

## v2.0.0 — 2026-04-28

The big one. v1.0 → v2.0 generalizes the v1.0 port into a project-agnostic Claude Code plugin and adds 12 phases of capability on top.

### Added — agents (4 new specialists)
- `@data-architect` — object model, sharing, LDV, migrations
- `@integration-architect` — callouts, Named Credentials, Platform Events, CDC, External Services
- `@e2e-tester` — UTAM (Lightning) / Playwright (Experience Cloud) end-to-end tests
- `@security-reviewer` — OWASP-for-SF, SOQL injection, IDOR, sharing/CRUD/FLS edge cases

### Added — skills (34 new)
- **Org awareness**: `org-explore`, `org-diff`, `flow-audit`, `permset-audit`, `field-impact`
- **Architecture**: `erd`, `sequence-diagram`, `adr`
- **Testing**: `test-plan`, `test-data`, `coverage-trend`, `flaky-test-finder`
- **Security**: `security-scan`, `fls-audit`, `sharing-review`
- **Performance**: `soql-analyzer`, `limit-usage`, `perf-review`
- **Deployment**: `diff-deploy`, `quick-deploy`, `scratch-org`, `package-version`, `release-notes`, `destructive-changes`
- **Code quality**: `dead-code`, `complexity`, `dependency-graph`
- **Workflow**: `onboard`, `pr-prepare`, `notify`, `pattern-pack`
- **Decision helpers**: `flow-vs-apex`, `before-vs-after-trigger`, `queueable-vs-batch`

### Added — patterns (6 new)
- `SF-15` — HTTP Callout via Named Credential
- `SF-16` — Apex REST Service
- `SF-17` — Custom Metadata Type Lookup
- `SF-18` — LWC Internationalization
- `SF-19` — Virtualized List for Large Datasets
- `SF-20` — Lazy-Loaded Sub-component

### Added — pattern packs (10)
- `platform-events` (v1.0, fully developed: PE-1..5)
- `change-data-capture` (v0.1 stub, structured for completion)
- `external-objects`, `big-objects`, `functions`, `field-service`, `industries`, `cms`, `einstein-agentforce`, `data-cloud` (v0.1 stubs)

### Added — infrastructure
- `hooks/lib/config.sh` — base + per-env override deep-merge
- `hooks/lib/sf-cli.sh` — Salesforce CLI wrapper
- `hooks/lib/pmd.sh` — lazy PMD downloader (pinned version)
- `hooks/lib/sarif.sh` — SARIF 2.1.0 emitter
- `hooks/lint-apex.sh` — PostToolUse PMD scan on `.cls`/`.trigger` edits
- `docs/ci-output-contract.md` — JSON + SARIF contract for CI integration
- `docs/pack-format.md` — pattern-pack format spec

### Added — bundled documentation
- 6 new patterns in `templates/docs/patterns/salesforce-patterns.md` (SF-15..20)
- New ADR template at `templates/docs/adr/0000-template.md`
- Scratch-org seed at `templates/scratch/seed.apex`
- 10 pack scaffolds under `templates/packs/`

### Changed — agent enhancements
- `@architect` output now includes Automation Type (Flow vs. Apex), Governor Limit Budget, Risk & Blast Radius, Effort Estimate, and Test Strategy blocks; reads org cache when present
- `@apex-dev` references SF-15/16/17 for callouts/REST/custom-metadata; SOQL selectivity guidance
- `@lwc-dev` references SF-18/19/20 for i18n/virtualization/lazy-load; LMS vs CustomEvent vs @wire decision matrix; LWS notes
- `@qa` enforces `Test.startTest`/`Test.stopTest` boundaries, ships HTTP/Queueable/Platform Event templates, **runs lint + tests + coverage** instead of just describing them

### Changed — skill enhancements
- `/sf-init` auto-detects existing SFDX state (`sfdx-project.json`, `package.json`, existing LWC prefix, `sf org list`); adds `update <fields>` and `env <name>` modes
- `/code-review` adds `pr` mode and full CI output (JSON / SARIF / `--fail-on`)
- `/test-coverage` adds CI mode and appends to coverage history for `/coverage-trend`
- `lint-lwc.sh` surfaces Prettier and ESLint failures clearly (no longer swallowed)

### Changed — config schema
- `platform.devHubAlias` (optional, used by `/scratch-org` and `/package-version`)
- `platform.packageName` (optional, used by `/package-version`)
- `notifications.webhooks.{slack,teams}` (optional, used by `/notify`)
- `notifications.channels.{deploy,coverage,security,release}` (optional routing)

### Per-environment overrides
- `.claude/sf-project.<env>.json` deep-merged over the base when `--env <name>` is passed
- All skills that read config honor the override path

### Migration from v1.x
1. Pull the new plugin version: `/plugin marketplace update sf-dev-kit`
2. Re-run `/sf-dev-kit:sf-init update` to pick up the auto-detect for fields you didn't set in v1
3. (Optional) Run `/sf-dev-kit:org-explore` to populate the org cache for `@architect`
4. Existing v1 workflows continue to work; new skills are additive
5. `notifications` config is optional — add it only when you want Slack/Teams posting

### Branching & versioning policy
v2 was built across 13 phase branches (`phase/0-foundation` through `phase/12-release`), each merged to `main` with `--no-ff` and tagged `v1.1.0`..`v2.0.0`. Going forward, new phases follow the same model: branch → commits → no-ff merge → tag.

---

## v1.0.0 — 2026-04-28

Initial port of an internal Salesforce AI workflow into a Claude Code plugin.

### Added
- 4 subagents (`@architect`, `@apex-dev`, `@lwc-dev`, `@qa`)
- 5 skills (`/sf-init`, `/code-review`, `/deploy`, `/generate-docs`, `/test-coverage`)
- 1 hook (`lint-lwc.sh`) — PostToolUse format + lint on LWC JS edits
- 14 reusable Salesforce patterns (SF-1..14)
- Bundled standards: `apex-standards.md`, `lwc-standards.md`, `quality-checklist.md`
- Project-aware `CLAUDE.md` template
- Plugin manifest + marketplace.json for `/plugin marketplace add`

The v1 plugin is a faithful port of an existing `.claude/` workflow from a private Salesforce DX project, generalized to be project-agnostic via `.claude/sf-project.json`.
