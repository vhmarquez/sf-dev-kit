# argo

> Opinionated, security-first AI workflow for Salesforce DX projects in Claude Code.

A Claude Code plugin that turns Claude into a Salesforce DX team. Eleven specialist subagents — solution architect, data architect, integration architect, Apex/LWC/React/agent builders, QA, E2E tester, security and trust reviewers — coordinate through structured handoffs. Fifty-six slash-skills handle setup, deploys, code review, agent dev, and DevOps. Every org-touching operation is gated by a hardened security model: production orgs are hard-blocked, customer-data queries require explicit per-call consent, and anonymous Apex is refused by default.

Built for Experience Cloud, Lightning Experience, Communities, mobile, and Slack delivery surfaces — and aware of everything Salesforce announced at TDX 2026 (Headless 360, Agentforce, the new React framework, the Einstein Trust Layer + AI Gateway controls, AgentExchange).

---

## Quickstart

Five steps from zero to a working setup, in your Salesforce DX project.

### 1. Install Claude Code (if you haven't)

```bash
# macOS / Linux
curl -fsSL https://claude.ai/install.sh | sh

# Windows: install from the Anthropic site or via npm
npm install -g @anthropic-ai/claude-code
```

### 2. Add the plugin

In Claude Code:

```text
/plugin marketplace add https://github.com/vhmarquez/argo
/plugin install argo@argo
```

Restart your session so the agents, skills, and hooks register.

### 3. Bootstrap your project

`cd` into your SFDX project, then:

```text
/argo:sf-init
```

Detection runs automatically (`sfdx-project.json`, `package.json`, `sf org list`, etc.) and presents one screen with everything pre-filled. You typically only fill in:
- A one-sentence project description
- Confirming the target org alias if multiple are detected
- Classifying any non-sandbox orgs as production (hard-blocked) or known-non-prod (allowed)

A smoke test runs after the write to verify the org alias resolves, paths exist, and lint commands work.

### 4. (Optional but recommended) Configure MCP

```text
/argo:mcp-setup --profile dev
```

Installs `@salesforce/mcp`, scopes the toolsets to a sensible dev set (`metadata, data, testing, lwc, code-analysis`), and writes `.mcp.json`. The plugin runs without it via direct `sf` CLI calls; MCP unlocks richer routing for Headless-360 features.

### 5. Try the workflow

```text
@architect: design a customer-greeting agent for our portal
```

The architect produces a structured plan (data model, automation type, governor budget, risk, effort, test strategy) and hands off to specialists — `@agent-dev` for the agent, `@apex-dev` for any Apex, `@react-dev` if the portal needs React, `@qa` to write tests, `@trust-reviewer` to check the agent surface. All in one conversation; specialists run in parallel where possible.

Before merging:

```text
/argo:code-review pr
/argo:security-scan
/argo:diff-deploy --validate
/argo:pr-prepare --push
```

That's the loop.

---

## Why this plugin

- **Salesforce DX-aware out of the box.** `/sf-init` reads `sfdx-project.json`, scans existing components for the LWC prefix, sniffs `package.json` for lint/test scripts, classifies orgs from `sf org list` — most of the config writes itself. You typically answer one or two questions.
- **Security is the default, not an afterthought.** Production orgs are unreachable; data queries require per-call consent; anonymous Apex is refused; every override is logged. Read [`docs/security-model.md`](docs/security-model.md) before loosening anything.
- **Specialists, not a generalist.** Eleven subagents with distinct responsibilities and clean handoffs. `@architect` plans, builders implement in parallel, reviewers gate the merge. No one agent has all the context — that's the point.
- **Headless 360 native.** First-class MCP routing via `@salesforce/mcp`, Agentforce dev workflow (`/agent-spec` → `/agent-test` → `/agent-deploy`), Trust Layer audits, AgentExchange listing prep, React-on-Salesforce parity with LWC.
- **CI-ready.** Most skills accept `--ci`, `--format json|sarif`, `--out`, `--fail-on` flags following a [documented contract](docs/ci-output-contract.md). SARIF output integrates natively with GitHub Code Scanning.

---

## Table of contents

- [Quickstart](#quickstart) — five steps to a working setup
- [Why this plugin](#why-this-plugin)
- [What you get](#what-you-get) — agents, skills, hooks, packs, standards
- [Install](#install) — full prerequisites
- [Project config](#project-config-claudesf-projectjson)
- [Security model](#security-model)
- [CI integration](#ci-integration)
- [Plugin layout](#plugin-layout)
- [Compatibility](#compatibility)
- [License](#license)
- [Changelog](#changelog)

---

## What you get

### Subagents (`agents/`) — 11 specialists

| Agent | Model | Role |
|-------|-------|------|
| `@architect` | opus | Read-only solution design + implementation plan (automation-type rec, governor budget, risk/blast-radius, effort, test strategy) |
| `@data-architect` | opus | Object model, master-detail vs lookup, sharing, LDV, migrations |
| `@integration-architect` | opus | Callouts, Named Credentials, Platform Events, CDC, External Services, **MCP Bridge**, **Trusted Agent Identity**, **Agent Fabric** |
| `@apex-dev` | sonnet | Apex implementation (classes, triggers, batch, queueable, REST, callouts, custom metadata) |
| `@lwc-dev` | sonnet | Lightning Web Component implementation (i18n, virtualization, lazy-load, LWS) |
| `@react-dev` | sonnet | **React-on-Salesforce** implementation (`@salesforce/react/graphql`, SLDS via tokens, LWC interop) |
| `@agent-dev` | sonnet | **Agentforce agent** authoring (topics, sub-agents, actions, prompts, eval suites) |
| `@qa` | sonnet | Apex + Jest tests; runs lint/tests/coverage; severity-graded code review |
| `@e2e-tester` | sonnet | UTAM (Lightning) / Playwright (Experience Cloud) end-to-end tests against scratch orgs |
| `@security-reviewer` | opus | OWASP-for-SF: SOQL injection, IDOR, sharing/CRUD/FLS edge cases |
| `@trust-reviewer` | opus | OWASP-for-LLM on agents: prompt injection, output validation, grounding leakage, jailbreak resistance |

Typical flow: `@architect` plans → hands off to specialists → builders work in parallel → `@qa` reviews → `@e2e-tester` covers journeys → `@security-reviewer` + `@trust-reviewer` before prod.

### Skills (`skills/`) — 56 total

Invoke any as `/argo:<name>`. Most accept `--ci`, `--format json|sarif`, `--out`, `--env <name>` per the [CI output contract](docs/ci-output-contract.md). Each skill declares a `data-access` field in its frontmatter (`none` / `metadata-only` / `data-with-consent`); see the [security model](#security-model).

**Setup & onboarding**
| Skill | Purpose |
|-------|---------|
| `/argo:sf-init` | Detect → review → edit → verify bootstrap. Aggressive auto-detection populates a single review screen with confidence markers; the user edits only what's ambiguous or required; a smoke test verifies the result. Modes: `auto`, `update <fields>`, `env <name>`, `verify` |
| `/argo:onboard` | Verify a developer's machine + smoke-test the dev loop end-to-end |
| `/argo:pattern-pack` | Install/list/info/remove domain pattern packs |
| `/argo:mcp-setup` | **Install/configure `@salesforce/mcp` toolsets** (metadata/data/testing/lwc/code-analysis/devops/aura) |

**Org awareness**
| Skill | Purpose |
|-------|---------|
| `/argo:org-explore` | Optional org-schema snapshot (in MCP mode, agents read live; cache is `--cache` opt-in) |
| `/argo:org-diff` | Source-vs-org drift report (setup-only / source-only / conflicts) |
| `/argo:flow-audit` | Active-flow inventory; flags Apex/Flow overlap and untracked-in-source flows |
| `/argo:permset-audit` | Object/field × principal access matrix; flags fields with no read access |
| `/argo:field-impact` | Field references across LWC, Apex, layouts, validation rules, formulas, flows, reports |
| `/argo:agent-discover` | **Agentforce agent inventory** — source vs org reconciliation; bridge tools per agent |

**Architecture & design**
| Skill | Purpose |
|-------|---------|
| `/argo:erd` | Mermaid ERD from `.object-meta.xml` (idempotent, depth-bounded) |
| `/argo:sequence-diagram` | Mermaid sequence from an LWC entry point through Apex / DB / external |
| `/argo:adr` | Architecture Decision Records under `docs/adr/` |
| `/argo:flow-vs-apex` | Flow vs Trigger vs Queueable vs Batch decision helper |
| `/argo:agent-vs-flow-vs-apex` | **Extends flow-vs-apex with Agent** as first-class option |
| `/argo:lwc-vs-react` | **Frontend framework decision** (LWC vs React vs both) |
| `/argo:mcp-tool-vs-rest` | **Integration pattern decision** (MCP Tool vs Apex REST vs Platform Event) |
| `/argo:before-vs-after-trigger` | Trigger phase decision |
| `/argo:queueable-vs-batch` | Async mechanism decision |

**Agent dev (Headless 360)**
| Skill | Purpose |
|-------|---------|
| `/argo:agent-spec` | Wrap `sf agent generate agent-spec` with project context; iterative refinement |
| `/argo:agent-test` | Run agent eval suite via Testing Center; per-axis severity (factuality, completeness, refusal-correctness, etc.) |
| `/argo:agent-eval-trend` | Per-agent eval history; PR-mode regression diff; security regressions zero-tolerance |
| `/argo:agent-deploy` | Deploy AgentDefinition + register evals; gates by trust-layer-audit + agent-test + eval-regression |
| `/argo:mcp-bridge` | **Wrap an Apex REST class as an MCP tool** — closes SF-16 → agent ecosystem loop |
| `/argo:slack-agent` | **Scaffold a Slack-native agent** end-to-end via Slack Agent Kit |
| `/argo:agent-exchange-list` | **Validate readiness for AgentExchange listing** |

**React (Headless 360)**
| Skill | Purpose |
|-------|---------|
| `/argo:react-init` | Scaffold a React component bundle with `@salesforce/react/graphql` + i18n + SLDS |

**Testing**
| Skill | Purpose |
|-------|---------|
| `/argo:test-plan` | Generate a structured test plan (positive/negative/bulk/edge/security) before writing tests |
| `/argo:test-data` | Scaffold an Apex `TestDataFactory` from sObject describes |
| `/argo:test-coverage` | Apex coverage **or** agent eval (modes: `apex` / `agent`) |
| `/argo:coverage-trend` | Coverage history; PR-mode regression gate |
| `/argo:flaky-test-finder` | Re-run a test class N times to identify non-deterministic methods |

**Code review & static analysis**
| Skill | Purpose |
|-------|---------|
| `/argo:code-review` | Per-component, batch (`all`/`audit`), and PR-mode review |
| `/argo:security-scan` | PMD `apex-security` ruleset; SARIF for GitHub Code Scanning |
| `/argo:fls-audit` | Static check for missing CRUD/FLS on DML / SOQL |
| `/argo:sharing-review` | `without sharing` audit; flag privilege escalation from `@AuraEnabled` |
| `/argo:soql-analyzer` | Selectivity check (indexed fields, LDV awareness, leading-wildcard) |
| `/argo:limit-usage` | Per-method governor-budget estimator |
| `/argo:perf-review` | LWC/React bundle size, @wire waterfall, render-blocking, missing virtualization |
| `/argo:dead-code` | Unused Apex methods/fields, LWC/React bundles, custom labels, custom permissions |
| `/argo:complexity` | Cyclomatic + cognitive complexity per method |
| `/argo:dependency-graph` | Apex call graph + LWC/React import graph |

**Trust & governance (Headless 360)**
| Skill | Purpose |
|-------|---------|
| `/argo:trust-layer-audit` | **Einstein Trust Layer config audit** (org-level + per-agent: PII masking, FLS-on-grounding, ZDR, jailbreak eval, etc.) |
| `/argo:trust-eval` | **Runtime drift audit** via Testing Center Custom Scoring Evals + Session Tracing sampling |
| `/argo:gateway-config` | **Generate/validate AI Gateway config** (model allowlist, token quotas, fallback chain) per environment |

**Deployment**
| Skill | Purpose |
|-------|---------|
| `/argo:deploy` | Deploy or `--validate` configured paths against the default org |
| `/argo:diff-deploy` | Deploy only metadata changed since `<ref>` |
| `/argo:quick-deploy` | Promote a validated deploy id to production without re-running tests |
| `/argo:scratch-org` | Create/destroy/recreate scratch orgs; seed Apex + agent data |
| `/argo:package-version` | 2GP/unlocked package version create/promote/list/install |
| `/argo:destructive-changes` | Interactive `destructiveChanges.xml` builder with reference validation |
| `/argo:devops-natural` | **Natural-language deploy** via DevOps Center MCP (Headless 360) |

**Documentation & release**
| Skill | Purpose |
|-------|---------|
| `/argo:generate-docs` | Generate or update LWC, Apex, React, and agent docs (`audit` mode flags stale/orphaned/missing) |
| `/argo:release-notes` | Conventional-commits release notes + ADRs + coverage stats |
| `/argo:pr-prepare` | Assemble a PR body from review/coverage/deploy/security gates |
| `/argo:notify` | Slack/Teams webhook poster for deploy/coverage/security/release events |

### Hooks (`hooks/`)

| Hook | Trigger | Action |
|------|---------|--------|
| `session-start.sh` | `SessionStart` | One-line first-run nudge when an SFDX project has no `.claude/sf-project.json` yet. Silent in all other cases |
| `security-guard.sh` | `PreToolUse` on `Bash` | Defense-in-depth security gate: refuses `sf` commands that target prod aliases or query data objects without consent. Belt-and-suspenders companion to `hooks/lib/security.sh`; see [`docs/security-model.md`](docs/security-model.md) |
| `lint-lwc.sh` | `PostToolUse` on `Edit`/`Write` of LWC JS | Prettier + ESLint; surfaces findings on stderr; never blocks |
| `lint-apex.sh` | `PostToolUse` on `Edit`/`Write` of `.cls`/`.trigger` | PMD `errorprone + bestpractices` |
| `lint-react.sh` | `PostToolUse` on `Edit`/`Write` of `.tsx`/`.jsx` (when `platform.frontend` includes react) | Prettier + ESLint |

Plus shared library helpers under `hooks/lib/`:
- `config.sh` — load and deep-merge project config + per-env overrides
- `sf-cli.sh` — wrappers for `sf` CLI; routes through `security.sh`; the always-works fallback
- **`mcp.sh`** — **`@salesforce/mcp` routing helpers** (`mcp_prefer`, `mcp_run <toolset> <tool>`, `mcp_list_tools`); routes through `security.sh`
- **`security.sh`** — **central security gate**: `sec_check_org`, `sec_check_soql`, `sec_check_anon_apex`, `sec_log_consent`, metadata allowlist. See [`docs/security-model.md`](docs/security-model.md)
- `pmd.sh` — lazy PMD download into `${CLAUDE_PLUGIN_DATA}` on first use
- `sarif.sh` — SARIF 2.1.0 emitter for `--format sarif`

### Domain pattern packs (`templates/packs/`) — 11 packs

Install via `/argo:pattern-pack add <name>`. Format documented in [`docs/pack-format.md`](docs/pack-format.md).

| Pack | Status | Patterns |
|------|--------|----------|
| **`agentforce`** | ✅ v1.0 | **AGT-1..7** — Agent topic boundaries, sub-agent decomposition, guardrails, MCP-tool actions, FLS-aware grounding, memory & state, escalation paths |
| **`react`** | ✅ v1.0 | **RX-1..6** — Platform GraphQL fetch, platform-aware auth, deployment, SLDS via tokens, i18n, LWC↔React interop |
| `platform-events` | ✅ v1.0 | PE-1..5 |
| `change-data-capture` | ✅ v1.0 | **CDC-1..5** — Source-controlled CDC selection, trigger subscriber + idempotency, Pub/Sub API, GAP_OVERFLOW reconciliation, CDC vs. PE decision |
| `external-objects` | ✅ v1.0 | **EXT-1..5** — Adapter selection, `__x` schema + Indirect/External Lookup, query/cache, write-back semantics, Custom Apex Connector |
| `big-objects` | ✅ v1.0 | **BIG-1..5** — Index design, `Database.insertImmediate`, Async SOQL aggregation, index-aligned predicates, lifecycle and capacity |
| `field-service` | ✅ v1.0 | **FS-1..5** — Work Order lifecycle, Service Appointment scheduling, Resource Absence + Operating Hours, mobile offline, territory design |
| `industries` | ✅ v1.0 | **IND-1..6** — OmniScript composition, FlexCards, Integration Procedures, DataRaptors, EPC, Apex extensions |
| `cms` | ✅ v1.0 | **CMS-1..5** — Content types, workspaces + channels, multi-locale variants, headless delivery, CMS vs Knowledge vs Files |
| `data-cloud` | ✅ v1.0 | **DC-1..5** — Data Streams + DLOs, DMOs + identity resolution, calculated insights + segments, activations, SQL API for Apex/agents |
| ~~`einstein-agentforce`~~ | ⚠️ deprecated | Renamed to `agentforce` in v2.5; redirect-only pack retained for back-compat with installs pinned to the old name |

### Bundled standards (`templates/docs/`)

Generic Salesforce standards copied into each new project by `/argo:sf-init`:

- `apex-standards.md` — governor limits, security, SOQL/DML, async, naming
- `lwc-standards.md` — CSS, JavaScript, accessibility, template directives
- `react-standards.md` — **React-on-Salesforce specifics** (only copied when `platform.frontend` includes react)
- `quality-checklist.md` — unified pre-flight checklist with **dedicated Agent + Trust Layer + AI Gateway sections**
- `patterns/salesforce-patterns.md` — **20 reusable patterns** SF-1..20 (base 14 + callouts + REST + custom metadata + i18n + virtualized list + lazy-load)

Plus stubs the user fills in:
- `project-context.md` — object model, channels, glossary, project-specific constraints
- `patterns/project-patterns.md` — project-specific patterns and shared components
- `adr/0000-template.md` — ADR template

---

## Install

### As a marketplace (recommended)

```text
/plugin marketplace add https://github.com/vhmarquez/argo
/plugin install argo@argo
```

### Local dev loop

```bash
claude --plugin-dir /path/to/argo
```

Restart the Claude Code session after install so agents, skills, and hooks register.

### Prerequisites

- **Salesforce CLI** (`sf`) — latest
- **Node.js** 20+
- **`@salesforce/mcp`** — recommended; the plugin runs without it (CLI fallback) but Headless 360 features unlock when available. Install: `/argo:mcp-setup`
- **git** 2.30+
- **jq** 1.6+
- **bash** 4+ (Git Bash on Windows)
- **Java** 11+ (only if using PMD-based skills: `/security-scan`, `/complexity`, `lint-apex.sh`)

PMD is downloaded automatically on first use of any PMD-based skill into `${CLAUDE_PLUGIN_DATA}/argo/pmd/<version>/`. Run `/argo:onboard` to verify all prerequisites.

---

## Project config (`.claude/sf-project.json`)

| Section | Keys | Notes |
|---------|------|-------|
| `project` | `name`, `description` | |
| `naming.lwc` | `prefix`, `excludePrefixes` | |
| `naming.react` | `prefix` | When `platform.frontend` includes react |
| `naming.apex` | suffixes | |
| `platform` | `apiVersion`, `defaultTargetOrg`, `lwcTargets`, `sharingDefault`, `devHubAlias`, `packageName`, **`frontend`** | `frontend` ∈ `"lwc" \| "react" \| "both"` |
| `paths` | `lwcSource`, `apexSource`, `reactSource`, `reactDocs`, **`agentDefinitions`**, `agentDocs`, `lwcDocs`, `apexDocs`, doc paths | |
| `quality` | `codeCoverageTarget`, `lintCommand`, `unitTestCommand`, **`agentEvalThreshold`** | Agent eval threshold default 0.85 (Trust Layer band) |
| **`mcp`** | **`toolsets`**, `allowNonGaTools` | Configured by `/argo:mcp-setup`; downstream skills route through `@salesforce/mcp` when present |
| `notifications.webhooks` | `slack`, `teams` | For `/notify` |
| **`security`** | **`prodOrgAliases`**, **`knownNonSandboxNonProd`**, **`metadataOnly`**, **`allowAnonymousApex`** | Restrictive defaults; see [security model](#security-model). Production aliases are **hard-blocked, no override** |

Per-environment overrides (`.claude/sf-project.<env>.json`) deep-merge over the base.

---

## Security model

The plugin enforces four hard invariants. Detailed model in [`docs/security-model.md`](docs/security-model.md):

1. **No contact with orgs classified as production** (`security.prodOrgAliases`). Hard refuse, no override.
2. **Metadata-only across all orgs by default.** SOQL queries must target the metadata allowlist (`ApexClass`, `EntityDefinition`, `Profile`, `Flow`, `AgentDefinition`, etc., plus any `*__mdt`). Customer-data targets (`Account`, custom `__c`, `AgentSessionTrace`, `User`, `ContentDocument`) require per-call user consent.
3. **Anonymous Apex disabled by default.** `sf apex run` is refused outright; even when enabled via `security.allowAnonymousApex: true`, every call prompts for consent.
4. **Overrides are runtime-only.** No persistent "always allow" grants. Every restricted call prompts.

Enforcement is centralized in `hooks/lib/security.sh` (every `sf-cli.sh` and `mcp.sh` wrapper routes through it) plus a `PreToolUse` Bash hook (`hooks/security-guard.sh`) that catches anything bypassing the library. Each skill declares its data-access surface in frontmatter (`data-access: none | metadata-only | data-with-consent`).

Three skills fundamentally need data access and prompt for consent every run: `/trust-eval` (queries `AgentSessionTrace`), `/permset-audit` (queries `PermissionSetAssignment`), `/agent-test` (eval inputs / outputs may carry test PII).

`/argo:sf-init` detects every non-sandbox alias `sf org list` knows about and requires the user to classify each one as production (refused) or known-non-prod (allowed) before writing config.

---

## CI integration

Skills with the `--ci` flag follow the [CI output contract](docs/ci-output-contract.md): JSON or SARIF output, exit codes per severity, configurable `--fail-on` threshold. SARIF integrates natively with GitHub Code Scanning.

A typical PR pipeline:

```yaml
- run: /argo:code-review pr --ci --format sarif --out review.sarif
- run: /argo:security-scan --ci --format sarif --out security.sarif
- run: /argo:trust-layer-audit --ci --format sarif --out trust.sarif
- run: /argo:agent-test --ci --fail-on error
- run: /argo:diff-deploy --validate --ci
- run: /argo:coverage-trend pr
- uses: github/codeql-action/upload-sarif@v3
  with: { sarif_file: review.sarif }
```

CI guidance: `ARGO_CONSENT_GRANTED` must never be set in CI. CI cannot grant consent; runs that would prompt fail loudly.

---

## Plugin layout

```
argo/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── agents/                    11 subagents
├── skills/                    56 skills (each with data-access frontmatter)
├── hooks/
│   ├── hooks.json
│   ├── session-start.sh, security-guard.sh
│   ├── lint-lwc.sh, lint-apex.sh, lint-react.sh
│   └── lib/                   config, sf-cli, mcp, security, pmd, sarif
├── templates/
│   ├── CLAUDE.md
│   ├── docs/                  bundled standards (apex/lwc/react), patterns, ADR template
│   ├── packs/                 11 domain pattern packs (10 full + 1 deprecated redirect)
│   ├── gateway/               AI Gateway config profiles (dev/qa/prod)
│   └── scratch/               seed.apex + seed-agents.apex
├── docs/
│   ├── ci-output-contract.md
│   ├── pack-format.md
│   └── security-model.md
├── README.md
├── CHANGELOG.md
└── .gitattributes / .gitignore
```

`${CLAUDE_PLUGIN_ROOT}` resolves to the plugin's installed location. `${CLAUDE_PLUGIN_DATA}` holds caches (org snapshots, PMD binary, coverage history, agent eval history, deploy history, consent log).

---

## Compatibility

- **Salesforce DX** — assumes `force-app/main/default/` layout (configurable via `paths.*`)
- **Experience Cloud / Lightning Experience** — `platform.lwcTargets` switches between `lightningCommunity__*` and `lightning__*Page` targets
- **Agentforce** — requires API ≥ 63.0 (set `platform.apiVersion`)
- **React-on-Salesforce** — requires API ≥ 63.0 + `platform.frontend` includes `react`
- **OS** — agents and skills are platform-agnostic; bash hooks run on macOS/Linux and Git Bash on Windows
- **Java** — required only for PMD-based skills

---

## Project status

`argo` is currently a **solo project** — I develop it primarily for my own use and ship it MIT-licensed so others can try it, fork it, and adapt it freely.

- **External contributions aren't accepted right now.** I'm keeping the dev process single-author for the moment to maintain a coherent design and security posture. **If the project gains enough traction that a contribution path makes sense, I'll revisit and publish a `CONTRIBUTING.md` at that point** — so this isn't a permanent "no," just a "not yet."
- **Security disclosures are welcome regardless of project stage.** See [`SECURITY.md`](SECURITY.md) for how to report a vulnerability privately via GitHub.
- **Bug reports** aren't actively solicited today — fork and fix locally is the supported path.
- The plugin is on GitHub for visibility and reuse, not (yet) to incubate a community around the codebase.

If you build something interesting on top, I'd love to hear about it.

---

## License

[MIT](LICENSE) — see the `LICENSE` file at the repo root.

---

## Trademarks

`argo` is an independent open-source project. It is **not** affiliated with, endorsed by, or sponsored by Salesforce, Inc. or Anthropic.

"Salesforce", "Apex", "Lightning", "Lightning Web Components", "Agentforce", "Experience Cloud", "Einstein Trust Layer", "OmniStudio", "Data Cloud", "MuleSoft", and other Salesforce product names referenced in this repository are trademarks of Salesforce, Inc., used here descriptively to indicate compatibility. "Claude" and "Claude Code" are trademarks of Anthropic, PBC.

All other trademarks are the property of their respective owners.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full v1.0.0 → v3.x history.
