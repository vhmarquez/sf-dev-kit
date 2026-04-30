# sf-dev-kit

A Claude Code plugin packaging an opinionated AI workflow for Salesforce DX projects — including the agent surface, the new React framework, and the MCP toolsets shipped with **Salesforce Headless 360** (TDX 2026). Built for Experience Cloud, Lightning Experience, Communities, mobile, and Slack delivery surfaces.

The workflow is driven by a single per-project config — **`.claude/sf-project.json`** — with optional per-environment overrides at `.claude/sf-project.<env>.json`. The plugin's `/sf-dev-kit:sf-init` skill scaffolds it interactively (auto-detects existing SFDX state).

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

Invoke any as `/sf-dev-kit:<name>`. Most accept `--ci`, `--format json|sarif`, `--out`, `--env <name>` per the [CI output contract](docs/ci-output-contract.md).

**Setup & onboarding**
| Skill | Purpose |
|-------|---------|
| `/sf-dev-kit:sf-init` | Detect → review → edit → verify bootstrap. Aggressive auto-detection populates a single review screen with confidence markers; the user edits only what's ambiguous or required; a smoke test verifies the result. Modes: `auto`, `update <fields>`, `env <name>`, `verify` |
| `/sf-dev-kit:onboard` | Verify a developer's machine + smoke-test the dev loop end-to-end |
| `/sf-dev-kit:pattern-pack` | Install/list/info/remove domain pattern packs |
| `/sf-dev-kit:mcp-setup` | **Install/configure `@salesforce/mcp` toolsets** (metadata/data/testing/lwc/code-analysis/devops/aura) |

**Org awareness**
| Skill | Purpose |
|-------|---------|
| `/sf-dev-kit:org-explore` | Optional org-schema snapshot (in MCP mode, agents read live; cache is `--cache` opt-in) |
| `/sf-dev-kit:org-diff` | Source-vs-org drift report (setup-only / source-only / conflicts) |
| `/sf-dev-kit:flow-audit` | Active-flow inventory; flags Apex/Flow overlap and untracked-in-source flows |
| `/sf-dev-kit:permset-audit` | Object/field × principal access matrix; flags fields with no read access |
| `/sf-dev-kit:field-impact` | Field references across LWC, Apex, layouts, validation rules, formulas, flows, reports |
| `/sf-dev-kit:agent-discover` | **Agentforce agent inventory** — source vs org reconciliation; bridge tools per agent |

**Architecture & design**
| Skill | Purpose |
|-------|---------|
| `/sf-dev-kit:erd` | Mermaid ERD from `.object-meta.xml` (idempotent, depth-bounded) |
| `/sf-dev-kit:sequence-diagram` | Mermaid sequence from an LWC entry point through Apex / DB / external |
| `/sf-dev-kit:adr` | Architecture Decision Records under `docs/adr/` |
| `/sf-dev-kit:flow-vs-apex` | Flow vs Trigger vs Queueable vs Batch decision helper |
| `/sf-dev-kit:agent-vs-flow-vs-apex` | **Extends flow-vs-apex with Agent** as first-class option |
| `/sf-dev-kit:lwc-vs-react` | **Frontend framework decision** (LWC vs React vs both) |
| `/sf-dev-kit:mcp-tool-vs-rest` | **Integration pattern decision** (MCP Tool vs Apex REST vs Platform Event) |
| `/sf-dev-kit:before-vs-after-trigger` | Trigger phase decision |
| `/sf-dev-kit:queueable-vs-batch` | Async mechanism decision |

**Agent dev (Headless 360)**
| Skill | Purpose |
|-------|---------|
| `/sf-dev-kit:agent-spec` | Wrap `sf agent generate agent-spec` with project context; iterative refinement |
| `/sf-dev-kit:agent-test` | Run agent eval suite via Testing Center; per-axis severity (factuality, completeness, refusal-correctness, etc.) |
| `/sf-dev-kit:agent-eval-trend` | Per-agent eval history; PR-mode regression diff; security regressions zero-tolerance |
| `/sf-dev-kit:agent-deploy` | Deploy AgentDefinition + register evals; gates by trust-layer-audit + agent-test + eval-regression |
| `/sf-dev-kit:mcp-bridge` | **Wrap an Apex REST class as an MCP tool** — closes SF-16 → agent ecosystem loop |
| `/sf-dev-kit:slack-agent` | **Scaffold a Slack-native agent** end-to-end via Slack Agent Kit |
| `/sf-dev-kit:agent-exchange-list` | **Validate readiness for AgentExchange listing** |

**React (Headless 360)**
| Skill | Purpose |
|-------|---------|
| `/sf-dev-kit:react-init` | Scaffold a React component bundle with `@salesforce/react/graphql` + i18n + SLDS |

**Testing**
| Skill | Purpose |
|-------|---------|
| `/sf-dev-kit:test-plan` | Generate a structured test plan (positive/negative/bulk/edge/security) before writing tests |
| `/sf-dev-kit:test-data` | Scaffold an Apex `TestDataFactory` from sObject describes |
| `/sf-dev-kit:test-coverage` | Apex coverage **or** agent eval (modes: `apex` / `agent`) |
| `/sf-dev-kit:coverage-trend` | Coverage history; PR-mode regression gate |
| `/sf-dev-kit:flaky-test-finder` | Re-run a test class N times to identify non-deterministic methods |

**Code review & static analysis**
| Skill | Purpose |
|-------|---------|
| `/sf-dev-kit:code-review` | Per-component, batch (`all`/`audit`), and PR-mode review |
| `/sf-dev-kit:security-scan` | PMD `apex-security` ruleset; SARIF for GitHub Code Scanning |
| `/sf-dev-kit:fls-audit` | Static check for missing CRUD/FLS on DML / SOQL |
| `/sf-dev-kit:sharing-review` | `without sharing` audit; flag privilege escalation from `@AuraEnabled` |
| `/sf-dev-kit:soql-analyzer` | Selectivity check (indexed fields, LDV awareness, leading-wildcard) |
| `/sf-dev-kit:limit-usage` | Per-method governor-budget estimator |
| `/sf-dev-kit:perf-review` | LWC/React bundle size, @wire waterfall, render-blocking, missing virtualization |
| `/sf-dev-kit:dead-code` | Unused Apex methods/fields, LWC/React bundles, custom labels, custom permissions |
| `/sf-dev-kit:complexity` | Cyclomatic + cognitive complexity per method |
| `/sf-dev-kit:dependency-graph` | Apex call graph + LWC/React import graph |

**Trust & governance (Headless 360)**
| Skill | Purpose |
|-------|---------|
| `/sf-dev-kit:trust-layer-audit` | **Einstein Trust Layer config audit** (org-level + per-agent: PII masking, FLS-on-grounding, ZDR, jailbreak eval, etc.) |
| `/sf-dev-kit:trust-eval` | **Runtime drift audit** via Testing Center Custom Scoring Evals + Session Tracing sampling |
| `/sf-dev-kit:gateway-config` | **Generate/validate AI Gateway config** (model allowlist, token quotas, fallback chain) per environment |

**Deployment**
| Skill | Purpose |
|-------|---------|
| `/sf-dev-kit:deploy` | Deploy or `--validate` configured paths against the default org |
| `/sf-dev-kit:diff-deploy` | Deploy only metadata changed since `<ref>` |
| `/sf-dev-kit:quick-deploy` | Promote a validated deploy id to production without re-running tests |
| `/sf-dev-kit:scratch-org` | Create/destroy/recreate scratch orgs; seed Apex + agent data |
| `/sf-dev-kit:package-version` | 2GP/unlocked package version create/promote/list/install |
| `/sf-dev-kit:destructive-changes` | Interactive `destructiveChanges.xml` builder with reference validation |
| `/sf-dev-kit:devops-natural` | **Natural-language deploy** via DevOps Center MCP (Headless 360) |

**Documentation & release**
| Skill | Purpose |
|-------|---------|
| `/sf-dev-kit:generate-docs` | Generate or update LWC and Apex docs |
| `/sf-dev-kit:release-notes` | Conventional-commits release notes + ADRs + coverage stats |
| `/sf-dev-kit:pr-prepare` | Assemble a PR body from review/coverage/deploy/security gates |
| `/sf-dev-kit:notify` | Slack/Teams webhook poster for deploy/coverage/security/release events |

### Hooks (`hooks/`)

| Hook | Trigger | Action |
|------|---------|--------|
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

Install via `/sf-dev-kit:pattern-pack add <name>`. Format documented in [`docs/pack-format.md`](docs/pack-format.md).

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

Generic Salesforce standards copied into each new project by `/sf-dev-kit:sf-init`:

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
/plugin marketplace add /path/to/sf-dev-kit
/plugin install sf-dev-kit@sf-dev-kit
```

### Local dev loop

```bash
claude --plugin-dir /path/to/sf-dev-kit
```

Restart the Claude Code session after install so agents, skills, and hooks register.

### Prerequisites

- **Salesforce CLI** (`sf`) — latest
- **Node.js** 20+
- **`@salesforce/mcp`** — recommended; the plugin runs without it (CLI fallback) but Headless 360 features unlock when available. Install: `/sf-dev-kit:mcp-setup`
- **git** 2.30+
- **jq** 1.6+
- **bash** 4+ (Git Bash on Windows)
- **Java** 11+ (only if using PMD-based skills: `/security-scan`, `/complexity`, `lint-apex.sh`)

PMD is downloaded automatically on first use of any PMD-based skill into `${CLAUDE_PLUGIN_DATA}/sf-dev-kit/pmd/<version>/`. Run `/sf-dev-kit:onboard` to verify all prerequisites.

---

## Use

In a Salesforce DX project (or a new directory you intend to make one):

1. **Bootstrap**
   ```text
   /sf-dev-kit:sf-init
   ```
   Auto-detects from `sfdx-project.json` and `package.json`; validates target org via `sf org list`. Set `platform.frontend` to `lwc`, `react`, or `both`. Set `mcp.toolsets` to enable Headless 360 routing.

2. **Configure MCP** (recommended)
   ```text
   /sf-dev-kit:mcp-setup --profile dev
   ```
   Installs `@salesforce/mcp`, scopes the toolsets, writes `.mcp.json`. After this, agent-mediated calls to the org route through the official MCP server.

3. **Fill in `docs/project-context.md`** — object model, channels, glossary, project-specific constraints.

4. **Build features through the workflow**
   ```text
   @architect: design a Slack-native order assistant
   ```
   The architect plans → hands off to `@agent-dev` (for the agent), `@apex-dev` (for the controller), `@react-dev` if the project also has a portal UI → `@qa` reviews → `@trust-reviewer` validates the agent surface.

5. **Verify before merge**
   ```text
   /sf-dev-kit:code-review pr
   /sf-dev-kit:test-coverage agent order_helper
   /sf-dev-kit:trust-layer-audit order_helper
   /sf-dev-kit:security-scan
   /sf-dev-kit:diff-deploy --validate
   /sf-dev-kit:pr-prepare --push
   ```

6. **Release**
   ```text
   /sf-dev-kit:devops-natural "deploy the order changes since main to prod"
   /sf-dev-kit:release-notes --update-changelog
   /sf-dev-kit:notify release '{"version":"2.0.0","url":"..."}'
   ```

7. **List on AgentExchange** (optional)
   ```text
   /sf-dev-kit:agent-exchange-list order_helper
   ```

---

## Project config (`.claude/sf-project.json`)

| Section | Keys | Notes |
|---------|------|-------|
| `project` | `name`, `description` | |
| `naming.lwc` | `prefix`, `excludePrefixes` | |
| `naming.react` | `prefix` | When `platform.frontend` includes react |
| `naming.apex` | suffixes | |
| `platform` | `apiVersion`, `defaultTargetOrg`, `lwcTargets`, `sharingDefault`, `devHubAlias`, `packageName`, **`frontend`** | `frontend` ∈ `"lwc" \| "react" \| "both"` |
| `paths` | `lwcSource`, `apexSource`, `reactSource`, `reactDocs`, **`agentDefinitions`**, `lwcDocs`, `apexDocs`, doc paths | |
| `quality` | `codeCoverageTarget`, `lintCommand`, `unitTestCommand`, **`agentEvalThreshold`** | Agent eval threshold default 0.85 (Trust Layer band) |
| **`mcp`** | **`toolsets`**, `allowNonGaTools` | Configured by `/sf-dev-kit:mcp-setup`; downstream skills route through `@salesforce/mcp` when present |
| `notifications.webhooks` | `slack`, `teams` | For `/notify` |

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

`/sf-dev-kit:sf-init` detects every non-sandbox alias `sf org list` knows about and requires the user to classify each one as production (refused) or known-non-prod (allowed) before writing config.

## CI integration

Skills with the `--ci` flag follow the [CI output contract](docs/ci-output-contract.md): JSON or SARIF output, exit codes per severity, configurable `--fail-on` threshold. SARIF integrates natively with GitHub Code Scanning.

A typical PR pipeline:

```yaml
- run: /sf-dev-kit:code-review pr --ci --format sarif --out review.sarif
- run: /sf-dev-kit:security-scan --ci --format sarif --out security.sarif
- run: /sf-dev-kit:trust-layer-audit --ci --format sarif --out trust.sarif
- run: /sf-dev-kit:agent-test --ci --fail-on error
- run: /sf-dev-kit:diff-deploy --validate --ci
- run: /sf-dev-kit:coverage-trend pr
- uses: github/codeql-action/upload-sarif@v3
  with: { sarif_file: review.sarif }
```

---

## Plugin layout

```
sf-dev-kit/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── agents/                    11 subagents
├── skills/                    56 skills
├── hooks/
│   ├── hooks.json
│   ├── lint-lwc.sh, lint-apex.sh, lint-react.sh
│   └── lib/                   config, sf-cli, mcp, pmd, sarif
├── templates/
│   ├── CLAUDE.md
│   ├── docs/                  bundled standards (apex/lwc/react), patterns, ADR template
│   ├── packs/                 11 domain pattern packs (10 full + 1 deprecated redirect)
│   ├── gateway/               AI Gateway config profiles (dev/qa/prod)
│   └── scratch/               seed.apex + seed-agents.apex
├── docs/
│   ├── ci-output-contract.md
│   └── pack-format.md
├── README.md
├── CHANGELOG.md
└── .gitattributes / .gitignore
```

`${CLAUDE_PLUGIN_ROOT}` resolves to the plugin's installed location. `${CLAUDE_PLUGIN_DATA}` holds caches (org snapshots, PMD binary, coverage history, agent eval history, deploy history).

---

## Compatibility

- **Salesforce DX** — assumes `force-app/main/default/` layout (configurable)
- **Experience Cloud / Lightning Experience** — `platform.lwcTargets` switches between `lightningCommunity__*` and `lightning__*Page` targets
- **Agentforce** — requires API ≥ 63.0 (set `platform.apiVersion`)
- **React-on-Salesforce** — requires API ≥ 63.0 + `platform.frontend` includes `react`
- **OS** — agents and skills are platform-agnostic; bash hooks run on macOS/Linux and Git Bash on Windows
- **Java** — required only for PMD-based skills

---

## License

MIT

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the v1.0.0 → v3.0.0 history.
