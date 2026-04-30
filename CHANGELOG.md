# Changelog

All notable changes to **sf-dev-kit**. Format follows [Keep a Changelog](https://keepachangelog.com/) and the project follows [SemVer](https://semver.org/).

---

## v3.3.0 — 2026-04-30

The "first impression" release. The plugin's value-prop now reads in 30 seconds, the quickstart is five copy-pasteable commands, and a SessionStart hook tells you what to run when you land in a fresh SFDX project. Same surface as v3.2; better discovery.

### Added — first-run experience

- **`hooks/session-start.sh`** — `SessionStart` hook that fires once per session. When `CLAUDE_PROJECT_DIR/sfdx-project.json` exists but `.claude/sf-project.json` doesn't, it emits a one-paragraph nudge pointing at `/sf-dev-kit:sf-init` (with surface-aware extras when React sources or AgentDefinitions are detected). Silent in every other case — never adds noise to projects that don't need it. Disable per-session via `SF_DEV_KIT_SESSION_NUDGE=0`.
- **`hooks/hooks.json`** — registers the `SessionStart` matcher with a 5s timeout.

### Changed — README

The README now leads with what the plugin is, then how to try it, then everything else:

- **Tagline + elevator pitch** at the top — one sentence and one paragraph that answer "what is this and why would I want it"
- **Quickstart section** — five literally copy-pasteable steps from "Claude Code installed" to "running through the @architect → builders → reviewers loop"
- **"Why this plugin"** — five-bullet differentiators (DX-aware, security-first, specialists not generalists, Headless-360 native, CI-ready)
- **Table of contents** for the reference material that follows
- The full skill / hook / pack inventory is preserved as the back half — it's reference material, not the front door

The previous `## Use` section was replaced by the cleaner Quickstart. Plugin layout, security model, CI integration, compatibility, license, changelog all preserved verbatim.

### Changed — marketplace metadata

Plugin and marketplace descriptions rewritten to lead with positioning ("opinionated, security-first AI workflow") rather than feature counts.

### Migration from v3.2.x

No breaking changes. Pull v3.3:

```text
/plugin marketplace update sf-dev-kit
```

The SessionStart hook is automatic and silent unless it has something useful to say. Existing projects (with `.claude/sf-project.json`) will see no behavior change.

---

## v3.2.0 — 2026-04-30

The "security model" release. The plugin now enforces four hard invariants on every org-touching operation: prod orgs are hard-blocked, SOQL is metadata-only by default, anonymous Apex is refused by default, and overrides are runtime-only. Centralized in a new `security.sh` library; defended in depth by a `PreToolUse` Bash hook that catches anything bypassing the library.

### Added — security infrastructure

- **`hooks/lib/security.sh`** — central security gate. Public functions:
  - `sec_check_org <alias>` — hard-refuses prod aliases; classifies unknown aliases via `sf org display`
  - `sec_check_soql <soql> <alias>` — parses FROM clause; refuses non-allowlist targets
  - `sec_check_anon_apex <alias>` — refuses unless `security.allowAnonymousApex: true` AND consent token set
  - `sec_check_data_write <alias> <action>` — refuses unless consent token set
  - `sec_classify_org <alias>` — caches sandbox/prod classification
  - `sec_log_consent` — appends to JSONL audit log
- **`hooks/security-guard.sh`** — `PreToolUse` hook on `Bash`. Defense-in-depth wrapper around raw `sf` commands that bypass the library helpers. Disable per-session via `SF_DEV_KIT_SECURITY_GUARD=0` (testing only)
- **`docs/security-model.md`** — full security-model documentation: invariants, wire protocol, exit codes, JSON event shape, consent UX, threat model, recommended posture
- **Org-classification cache** at `${CLAUDE_PLUGIN_DATA}/sf-dev-kit/org-cache/<alias>.json`
- **Consent log** at `${CLAUDE_PLUGIN_DATA}/sf-dev-kit/consent-log/<project>.jsonl` — every override granted, with timestamp, skill, action, scope

### Added — config schema

- `security.prodOrgAliases` — aliases the plugin refuses to contact, ever (no override)
- `security.knownNonSandboxNonProd` — non-sandbox orgs classified as OK (dev orgs, demo orgs)
- `security.metadataOnly` (default `true`) — SOQL must target the metadata allowlist; otherwise per-call consent
- `security.allowAnonymousApex` (default `false`) — `sf apex run` is refused outright when false

### Added — wire protocol

When a security check refuses, the function emits a JSON event on stderr and exits with one of:

- `77` — consent required (overridable). Assistant presents to user; on grant, re-invokes with `SF_DEV_KIT_CONSENT_GRANTED=once` (single-use token)
- `78` — hard refusal (not overridable in this session)
- `2` — invocation error

Event shape: `{event, reason, skill, action, target, org, message}`.

### Changed — wrappers

- **`hooks/lib/sf-cli.sh`** — every org-touching function routes through `security.sh`. `sf_cli_query` runs `sec_check_soql`; `sf_cli_describe` / `sf_cli_org_display` / `sf_cli_list_objects` run `sec_check_org`. `sf_cli_alias_exists` is local-only and unchanged.
- **`hooks/lib/mcp.sh`** — `mcp_run` runs `_mcp_security_check`, which routes by `(toolset, tool)` pair: data toolset SOQL → `sec_check_soql`; data writes → `sec_check_data_write`; anon Apex → `sec_check_anon_apex`.

### Changed — sf-init

- Detection now classifies every non-scratch alias `sf org list` knows about via `sf org display --json` (cached). Any alias reporting `isSandbox: false` and not yet listed in `security.prodOrgAliases` or `security.knownNonSandboxNonProd` surfaces on the review screen as ⚠️ required — must be classified before write proceeds.
- Schema includes the new `security` block; written by default with restrictive values
- Verify step gains three checks: all non-sandbox orgs classified; security defaults intact; `defaultTargetOrg` not in prod list
- Field help (`? <N>`) covers each new security field

### Changed — data-touching skills (now require explicit consent)

- **`/trust-eval`** — queries `AgentSessionTrace` (user conversation transcripts). Frontmatter declares `data-access: data-with-consent`. Refused on prod orgs. Per-run consent block lists: org, action, record scope, what enters Claude's context.
- **`/permset-audit`** — queries `PermissionSetAssignment` (user-permset links). Frontmatter declares `data-access: data-with-consent`. Other queries (`Profile`, `PermissionSet`, `ObjectPermissions`, `FieldPermissions`) remain on the metadata allowlist and don't prompt. Offers `[d] Deny this part` to skip the assignments query and run a partial audit.
- **`/agent-test`** — runs `sf agent test run` (eval inputs / outputs may carry test PII). Frontmatter declares `data-access: data-with-consent`. Production orgs blocked outright.

### Changed — frontmatter audit

Every skill now declares its data-access surface in frontmatter:

| Value | Count | Meaning |
|-------|-------|---------|
| `data-access: none` | 30 | No org contact at all |
| `data-access: metadata-only` | 23 | May contact orgs, but only metadata-shaped ops; SOQL constrained by allowlist |
| `data-access: data-with-consent` | 3 | Fundamentally needs customer data; prompts every run |

### Changed — hooks.json

- Adds a `PreToolUse` matcher on `Bash` registering `security-guard.sh` (10s timeout). Existing `PostToolUse` lint hooks unchanged.

### Migration from v3.1.x

1. Pull v3.2: `/plugin marketplace update sf-dev-kit`
2. Re-run `/sf-dev-kit:sf-init update` (or the full bootstrap) to populate the new `security` block. Required: classify every non-sandbox alias as either prod or known-non-prod
3. (Recommended) Run `/sf-dev-kit:sf-init verify` to confirm the new boundary holds against your config
4. Existing skills continue to work with no changes — the security library refuses what it must; data-touching skills surface consent prompts at runtime
5. CI: ensure `SF_DEV_KIT_CONSENT_GRANTED` is **never set** in the env. CI cannot grant consent; runs that would prompt instead fail loudly

### Notes on threat model

What's protected:
- Accidental writes / queries against prod (alias-list block + classification cache)
- Skill-prompt injection asking Claude to "run a query against the customer table" (allowlist refuses non-metadata SOQL)
- Future skill updates that add unintended data queries (Bash guard catches at hook layer)
- Privilege escalation via anonymous Apex (refused by default)

What isn't:
- Compromise of the user's local `sf` CLI auth state
- The user explicitly setting `prodOrgAliases: []` and consenting to every prompt
- Vulnerabilities in `@salesforce/mcp` itself
- Information that flows to the Anthropic API as part of the standard Claude Code session — same data flow as any other Claude Code project

---

## v3.1.0 — 2026-04-30

The "fill-in-the-stubs" release. v3.0 shipped 3 fully-authored domain packs and 8 stub scaffolds; v3.1 finishes the stubs (now 7 of 8, with the 8th — `functions` — dropped because Salesforce Functions is retired), drags V1-era skills into v3 parity, and tightens the deprecated-pack story.

### Added — pattern packs (7 new, all v1.0)

- **`change-data-capture` v1.0** — **CDC-1..5**: source-controlled CDC selection (`PlatformEventChannelMember` metadata), Apex trigger subscriber with `(commitNumber, sequenceNumber)` idempotency and `GAP_*` handling, external Pub/Sub API subscriber with bytes-shaped replayId, `GAP_OVERFLOW` reconciliation via Bulk-API diff, CDC vs. Platform Events decision matrix
- **`external-objects` v1.0** — **EXT-1..5**: adapter selection (OData 4 / OData 2 / Cross-Org / Custom Apex), `__x` schema with Indirect/External Lookup, query callout-budget guarding + Platform Cache, write-back semantics + partial-failure handling, Custom Apex Connector via `DataSource.Connection`/`Provider`
- **`big-objects` v1.0** — **BIG-1..5**: index design (immutable; permanent), `Database.insertImmediate` and Bulk API 2.0 writes, Async SOQL aggregation into rollup sObjects, index-aligned predicates, capacity tier and decommission rehearsal
- **`field-service` v1.0** — **FS-1..5**: Work Order lifecycle keyed off `Status.Category`, Service Appointment scheduling fields owned by the engine, `ResourceAbsence` + `OperatingHours` + `TimeSlot`, mobile-offline idempotency via `External_Key__c`, Service Territory Primary/Secondary membership
- **`industries` v1.0** (renamed from "Vlocity") — **IND-1..6**: OmniScript composition + embedded scripts, FlexCards for read-only surfaces, Integration Procedures with cache, DataRaptors (Extract/Turbo/Transform/Load), Enterprise Product Catalog, Apex extensions via `omnistudio.VlocityOpenInterface`
- **`cms` v1.0** — **CMS-1..5**: custom `ManagedContentType`, workspaces vs. channels + programmatic publishing via ConnectApi, multi-locale variants honoring `@salesforce/i18n/lang`, headless delivery via Connect Delivery API + CDN caching, CMS vs. Knowledge vs. Files decision
- **`data-cloud` v1.0** — **DC-1..5**: Data Streams + Data Lake Objects, Data Model Objects + identity resolution, calculated insights + segments, activation to external systems with Named Credentials and suppression lists, Data Cloud SQL API for Apex / agent grounding (Data Spaces, caching, query budgets)

Each pack ships `patterns.md`, `checklist.md`, `README.md`, and `pack.json`.

### Added — bundled doc scaffolds

- `templates/docs/react/README.md` — React component index stub, copied by `/sf-init` when `platform.frontend ∈ {react, both}`
- `templates/docs/agents/README.md` — Agentforce agent index stub, copied by `/sf-init` when `paths.agentDefinitions` is configured

### Changed — skills (V3 parity for V1-era skills)

- **`/sf-init`** — Step 3's example JSON now reflects the v3 schema (adds `mcp.toolsets`, `platform.frontend`, `naming.react`, `paths.reactSource`, `paths.reactDocs`, `paths.agentDefinitions`, `paths.agentDocs`, `quality.agentEvalThreshold`, `notifications.webhooks`); Step 6 scaffolds `docs/react/README.md` and `docs/agents/README.md` when those surfaces are in scope. Documents which keys are conditional vs. unconditional
- **`/code-review`** — Pattern Compliance table now lists SF-1..**SF-20** (was SF-1..SF-13) plus an explicit row for pack-installed prefixes (AGT-* / RX-* / PE-* / CDC-* / etc.); audit-mode header text updated to match
- **`/generate-docs`** — adds React component + Agentforce agent doc generation, scoping rules per surface, full CI flag set (`--ci`, `--format json|sarif`, `--out`, `--fail-on`, `--env`), `<!-- manual:keep -->` block preservation. New rule IDs: `DOCS-MISSING`, `DOCS-STALE`, `DOCS-ORPHANED`, `DOCS-INDEX-DRIFT`
- **`/deploy`** — adds `--ci`, `--env`, `--mcp`/`--no-mcp`, `--tests <level>`, MCP `metadata`-toolset routing (with CLI fallback when `mcp.toolsets` is read-only), React-bundle support, deploy-history JSONL append for `/quick-deploy` to consume, production-confirmation rule (`DEPLOY-PROD-REQUIRES-EXPLICIT`)
- **`/pattern-pack`** — `add` honors a new `deprecated: true` field in `pack.json`: refuses to install the deprecated pack and prints the migration command pointing at `supersededBy`. Skill description updated to list current packs (Agentforce, React, Platform Events, CDC, External Objects, Big Objects, Field Service, Industries, CMS, Data Cloud)
- **`/agent-discover`** — fixed an outdated reference: the Agent Registry is populated by `/sf-dev-kit:mcp-bridge --register`, not `/sf-dev-kit:mcp-setup`

### Changed — template doc indexes

- `templates/docs/README.md` — generic patterns range now `SF-1..20` (was `SF-1..14`); adds React + Agents component indexes; adds an ADR section
- `templates/CLAUDE.md` — pattern-pack list updated to enumerate all 10 full packs (was "8 stub packs ready to author")

### Changed — deprecated pack handling

- `templates/packs/einstein-agentforce/` — `pack.json` now declares `deprecated: true` + `supersededBy: agentforce` and nulls out `installs.patternsAppendTo`/`checklistAppendTo` so an accidental `add` no longer half-installs anything; `patterns.md` rewritten as a redirect to `agentforce` (no more `_TODO_` placeholders); version bumped 0.1.0 → 0.2.0 to mark the cleanup. Directory still kept for back-compat with installs pinned to the old name; will be removed in a future major

### Removed

- **`templates/packs/functions/`** — dropped entirely. Salesforce Functions is retired; the pack was a stub. Removed from `README.md`, `templates/CLAUDE.md`, and `docs/pack-format.md`'s example domain list. The `CHANGELOG` v2.0.0 historical entry is preserved verbatim
- The "8 stub packs" callout in `templates/CLAUDE.md` — superseded by the per-pack list above

### Migration from v3.0.x

1. Pull v3.1: `/plugin marketplace update sf-dev-kit`
2. Existing pack installs continue to work; no schema changes
3. (Optional) Install any of the seven newly-authored packs:
   ```text
   /sf-dev-kit:pattern-pack add change-data-capture
   /sf-dev-kit:pattern-pack add data-cloud
   ...
   ```
4. (Optional but recommended) If your project's `.claude/sf-project.json` was written before v3, re-run `/sf-dev-kit:sf-init update` to align with the v3 schema documented in the updated Step 3
5. If your project pinned the deprecated `einstein-agentforce` pack:
   ```text
   /sf-dev-kit:pattern-pack remove einstein-agentforce
   /sf-dev-kit:pattern-pack add agentforce
   ```
6. If your project pinned the dropped `functions` pack: remove it from `.claude/sf-dev-kit-packs.json` manually (the pack directory no longer ships)

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
