# Changelog

All notable changes to **argo**. Format follows [Keep a Changelog](https://keepachangelog.com/) and the project follows [SemVer](https://semver.org/).

> **Note on the project's name.** The project was renamed from **`sf-dev-kit`** to **`argo`** in v4.0.0. CHANGELOG entries from v1.0.0 through v3.3.3 originally referenced `sf-dev-kit`; they've been updated to use `argo` for consistency with the current project identity. The historical commits (`fdb8819` and earlier through `5459c44`) on the master branch preserve the original `sf-dev-kit` wording for the record. If you're upgrading from an older install, see the v4.0.0 migration guide below.

---

## v4.4.0 — 2026-05-29

### Added — test suite

- **A [bats](https://github.com/bats-core/bats-core) suite over the security-critical hooks** under `tests/`, exercising the enforcement contract by faking the `sf` CLI boundary (no org, network, or credentials needed). Run with `bash tests/run.sh` (or `bats tests/`). Closes the "no automated tests" gap from the review.
  - `security_guard.bats` — the PreToolUse guard as a black box (JSON in → exit code): compound-command bypass, path-qualified/quoted `sf`, inline consent token, metadata-vs-data SOQL, no false positives on `git && sf deploy`.
  - `classify.bats` — `security.sh` functions directly (real `77`/`78` codes): scratch→`dev`, sandbox, prod, `prodOrgAliases` hard-refuse, `knownNonSandboxNonProd`, no-cache-on-unknown, TTL re-derive, cache short-circuit, metadata-only-is-unconditional.
  - `pmd.bats` — sha256 helper correctness + the pinned-hash invariant.
  - `tests/helpers/` — a configurable fake `sf` and shared bats setup (isolated temp dirs, `seed_cache`, `guard`, `load_security_lib`).
- **No CI workflow, by design.** `tests/README.md` documents a free, opt-in local `pre-push` hook to gate your own pushes.

---

## v4.3.0 — 2026-05-29

Second hardening pass (the original review's "Phase 2"). Robustness and supply-chain fixes; no breaking changes.

### Security

- **Scratch orgs are now classified as a non-prod `dev` tier and allowed** without explicit classification. Previously `isSandbox=false` mapped straight to `prod`, so scratch orgs — the primary SFDX dev target — were hard-blocked until manually added to `security.knownNonSandboxNonProd`. Classification now checks `sf org list`'s `scratchOrgs` first; a production org can never appear there, so the signal cannot promote a prod org to allowed. (Developer-Edition orgs remain non-scratch → `prod` until explicitly classified.)
- **Fixed an `isSandbox` parse bug in org classification.** `jq -r '.result.isSandbox // …'` coalesced a literal `false` to the next branch (same `//` gotcha as the removed `metadataOnly`), so a real prod org was mislabeled `unknown` (and never cached). Both paths still *blocked*, but `prod` now classifies, caches, and emits the correct event/`78`-on-consent behavior.
- **PMD download is integrity-checked.** `pmd.sh` now verifies the downloaded `pmd-dist-<version>-bin.zip` against a pinned SHA-256 before extracting/executing, and **fails closed** (deletes the artifact, refuses to extract) on mismatch. Pinned for the default version; override via `ARGO_PMD_SHA256` when bumping `ARGO_PMD_VERSION`.
- **Lint hooks pass file paths after a `--` terminator.** `lint-lwc.sh` / `lint-react.sh` now run `npx … prettier/eslint -- "$FILE_PATH"`, preventing a path that begins with `-` from being parsed as an option. Added the missing `set -u` to `lint-lwc.sh`.

### Changed

- **Org-touching skills route data queries through the library.** `permset-audit`, `trust-eval`, `flow-audit`, and `field-impact` now call `sf_cli_query` instead of raw `sf data query`, so the metadata-allowlist consent gate fires at the documented library layer (the PreToolUse guard remains the backstop). For `permset-audit`, the `PermissionSetAssignment` (customer-data) query now prompts for consent exactly as the skill's `data-with-consent` declaration claims.
- **`@e2e-tester`**: clarified that anonymous Apex for test-data setup is refused by default (requires `allowAnonymousApex` + per-call consent, scratch only); prefer the REST setup path.
- **`@trust-reviewer`**: scoped its "read-only" claim to source/code/config and noted that runtime assessment executes agent eval runs which invoke the agent in a non-prod org (gated as agent-eval).

---

## v4.2.0 — 2026-05-29

Removed the plugin's non-functional MCP routing layer. `hooks/lib/mcp.sh` invoked a one-shot CLI surface on `@salesforce/mcp` (`--invoke`/`--args`/`--list-tools`) that does not exist — `@salesforce/mcp` is a stdio MCP server — so every "route through MCP" path silently failed and fell back to (or, for fictional tools, did nothing on) the `sf` CLI. Rather than build a second MCP client, the plugin now relies solely on the gated `sf` CLI library, which keeps a single enforced security path. MCP as a Salesforce *platform* capability (Agentforce agents exposing/calling MCP tools) is unaffected and still documented.

> **Breaking:** three skills are removed. If you scripted them, migrate as noted below.

### Removed

- **`hooks/lib/mcp.sh`** — the fake routing client (`mcp_prefer`, `mcp_run`, `mcp_list_tools`, `mcp_check`).
- **`/argo:mcp-setup`** — installed/configured the MCP server for plugin routing. No replacement; if you want the native Salesforce MCP server available to Claude Code's model directly, configure it in `.mcp.json` yourself (note: native MCP tool calls are not gated by argo's security guard).
- **`/argo:mcp-bridge`** — "wrap an Apex REST endpoint as an MCP tool"; built on a non-existent `@salesforce/mcp-bridge-runtime` package and a fictional `register-agent-tool` operation.
- **`/argo:devops-natural`** — "natural-language deploy via DevOps Center MCP"; built on a fictional `parse-deploy-request` tool. Use **`/argo:diff-deploy`** or **`/argo:deploy`** instead.
- Skill count: **56 → 53**.

### Changed

- **All org-touching skills now use the `sf` CLI library only.** `org-explore`, `agent-discover`, `trust-layer-audit`, `deploy`, and `agent-deploy` had `if mcp_prefer; then mcp_run …; else <sf CLI>; fi` blocks collapsed to the CLI path (which was always the one that actually worked, and is gated by `security.sh`).
- **`/argo:sf-init`** no longer writes a `mcp` config block or scaffolds `.mcp.json`.
- **Dropped "Headless 360 native (MCP routing)" positioning** from `plugin.json`/`marketplace.json`/`README` (and the `headless360` marketplace keyword). The genuine Agentforce / Trust Layer / AI Gateway / AgentExchange coverage is unchanged.
- **Kept** the `mcp-tool-vs-rest` decision skill and the Agentforce pack patterns describing agents that expose/call MCP tools — that is accurate platform guidance, independent of the removed routing.

---

## v4.1.0 — 2026-05-29

Security hardening of the enforcement layer plus an honesty pass on the docs. No skill, agent, or pack content changed; behavior changes are confined to the security guard and library.

### Security

- **PreToolUse guard is no longer bypassable by command chaining.** `security-guard.sh` previously classified only the *first* `sf` invocation in a command, so a benign leading verb (`sf org list; sf data query … -o prod`) let a later prod-targeted query, anonymous Apex, or data write run ungated. The guard now splits the command on shell separators (`;` `&&` `||` `|` `&` newline) and gates **every** `sf` segment independently.
- **Path-qualified and quoted `sf` are now detected.** `/usr/local/bin/sf …` and `'sf' …` were not matched by the old bail regex and ran ungated; detection is now basename-aware. (Shell indirection — `$VAR`, `eval`, aliases — remains out of scope and is now documented as such.)
- **Guard fails closed without `jq`.** Previously it exited 0 (allow-all) when `jq` was missing; it now refuses recognizably-dangerous patterns (`sf data …`, `sf apex run`, `sf agent run/test`) and only fails open for clearly-benign commands.
- **Org-classification cache is no longer a permanent trust anchor.** Verdicts now carry an epoch + `username` stamp and expire after `ARGO_ORG_CACHE_TTL` (default 7 days); `unknown` is never cached (transient failures self-heal); an alias re-authed to a different org can't ride a stale `sandbox` verdict. `prodOrgAliases` is still consulted *before* the cache on every call.
- **State files tightened to `0600`/`0700`.** The org-cache and consent-log directories and files (which hold org metadata + activity history) are no longer world-readable.

### Fixed

- **Consent re-invoke now works through the guard.** The documented `ARGO_CONSENT_GRANTED=once sf …` form is parsed out of the command and honored for that single call; previously the guard read the token only from its own environment, so a command prefix could never grant consent and raw `sf` data queries were blocked forever.
- **Refusal messages no longer execute `sf`.** Two messages in `security.sh` contained unescaped backticks (`` `sf org display` ``) that bash command-substituted while building the string — running a live `sf org display` against the default org and leaking its output into the emitted event. Replaced with literal text.
- **Removed the no-op `security.metadataOnly` config field.** It was written by `/argo:sf-init` and documented in several places but never read by the enforcement code. Rather than implement an opt-out, the metadata-only SOQL allowlist is now **unconditional**: the plugin only ever auto-allows allowlisted metadata SOQL, and customer-data reads always require per-call consent on every org — with no toggle to loosen it. The field is no longer written by `sf-init`, documented, or recognized.
- **Hook scripts are marked executable.** `security-guard.sh`, `session-start.sh`, and the three lint hooks are now committed with mode `755` so the hook layer runs on a fresh install.
- **Repo URL unified to `vhmarquez/argo`** in `hooks/lib/sarif.sh` (SARIF `informationUri`) and `docs/ci-output-contract.md`.

### Changed — docs

- `docs/security-model.md`: documented the guard's split-and-gate-every-segment behavior and added a **Known limitations** section (shell indirection, `jq`-absent fail-closed, default-org gating); scoped the 77/78/2 exit-code table to the library (the guard collapses to exit 2); corrected the consent-log description to "grants only"; refreshed the org-classification section (TTL, no-cache-unknown, integrity note).
- `README.md`: "production orgs are unreachable" → "blocked by default", with a pointer to Known limitations.

---

## v4.0.0 — 2026-04-30

The rename. The project is now **argo**. Every internal reference, environment variable, slash-command prefix, install-log filename, hook-log tag, and SARIF tool id has been updated. No skill, agent, hook, or pack content changed — this is a pure identity migration.

### Changed — identity

- **Plugin name**: `sf-dev-kit` → `argo` (in `.claude-plugin/plugin.json` and `marketplace.json`)
- **Slash-command prefix**: `/sf-dev-kit:<skill>` → `/argo:<skill>` (across all 56 skills, 11 agents, 11 packs, hooks, and docs)
- **Plugin data namespace**: `${CLAUDE_PLUGIN_DATA}/sf-dev-kit/` → `${CLAUDE_PLUGIN_DATA}/argo/` (org cache, consent log, deploy history, agent eval history, PMD binary cache)
- **Install log file**: `.claude/sf-dev-kit-packs.json` → `.claude/argo-packs.json`
- **Hook log tags**: `[sf-dev-kit/<surface>]` → `[argo/<surface>]` (security-guard, lint-lwc, lint-apex, lint-react, mcp, security)
- **SARIF tool ids**: `sf-dev-kit/code-review`, `sf-dev-kit/security-scan`, etc. → `argo/<skill>`
- **Environment variables**:
  - `SF_DEV_KIT_CONSENT_GRANTED` → `ARGO_CONSENT_GRANTED`
  - `SF_DEV_KIT_SECURITY` → `ARGO_SECURITY`
  - `SF_DEV_KIT_SECURITY_GUARD` → `ARGO_SECURITY_GUARD`
  - `SF_DEV_KIT_MCP_DISABLED` → `ARGO_MCP_DISABLED`
  - `SF_DEV_KIT_SESSION_NUDGE` → `ARGO_SESSION_NUDGE`

### Migration from v3.3.x

This is a **breaking change** for anyone with an installed v3.3.x. To migrate:

1. **Update the marketplace pointer** to the new repo URL (after the GitHub repo rename):
   ```text
   /plugin marketplace remove sf-dev-kit
   /plugin marketplace add https://github.com/vhmarquez/argo
   /plugin install argo@argo
   ```
2. **Update slash-command invocations** in any scripts, runbooks, or CI pipelines: `/sf-dev-kit:foo` → `/argo:foo`
3. **Rename the install log** in your projects (one-time): `mv .claude/sf-dev-kit-packs.json .claude/argo-packs.json`
4. **Migrate plugin data** if you want to preserve org-cache, consent-log, deploy-history (one-time):
   ```bash
   mv "${CLAUDE_PLUGIN_DATA}/sf-dev-kit" "${CLAUDE_PLUGIN_DATA}/argo"
   ```
   Skipping this step is fine — the new namespace will populate fresh on first use.
5. **Update environment variables** in any CI / shell config: `SF_DEV_KIT_*` → `ARGO_*` (rare; most users don't export these)
6. **Re-run** `/argo:sf-init verify` to confirm the new layout resolves cleanly.

The v3.3.3 release remains tagged in git; nothing in your existing v3.3.x install stops working — it's just decoupled from this repo's future updates after the GitHub repo rename.

### Why "argo"

Cleaner, shorter, more memorable than the descriptive `sf-dev-kit`. Doesn't lock the project into "Salesforce" forever (the AI-workflow patterns generalize), and doesn't read as Salesforce-affiliated (the original name leaned that way). Argo has good ship-and-crew connotations — fitting for a tool that coordinates a team of specialists.

---

## v3.3.3 — 2026-04-30

### Added

- **README "Trademarks" section** — explicit disclaimer that the project is independent, not affiliated with or endorsed by Salesforce, Inc. or Anthropic, and that referenced product names (Salesforce, Apex, Lightning, LWC, Agentforce, Experience Cloud, Einstein Trust Layer, OmniStudio, Data Cloud, MuleSoft, Claude, Claude Code, etc.) are trademarks of their respective owners, used descriptively to indicate compatibility.

Doc-only; no code or behavior changes.

---

## v3.3.2 — 2026-04-30

### Changed

- **README "Project status"** and **`SECURITY.md` "Bug reports"** sections — softened the contribution stance from "no contributions, ever" to "no contributions yet." If the project gains enough traction that a contribution path makes sense, a `CONTRIBUTING.md` will be published at that point. Today's posture is unchanged (still no PRs / feature requests accepted), but the messaging now says "not yet" instead of "never."

Doc-only tweak; no code or behavior changes.

---

## v3.3.1 — 2026-04-30

Repo hygiene — adds the missing legal/governance files and clarifies the project's contribution stance up front.

### Added

- **`LICENSE`** at the repo root — full MIT license text with copyright assigned to Victor Marquez. The README has always declared MIT, but without a `LICENSE` file the project was technically unusable downstream. This unblocks adoption at any company with a standard OSS-intake review.
- **`SECURITY.md`** — vulnerability reporting policy. Routes confidential reports through GitHub Private Vulnerability Reporting; lists what does and doesn't count as a security issue (with concrete examples — bypass of `prodOrgAliases`, missed consent prompts, hook-script command injection); sets expectations on solo-project response time and 90-day disclosure preference.
- **README "Project status" section** — explicit statement that this is a solo project: no PRs, feature requests, or external contributions accepted; security disclosures welcome; fork freely. Sets expectations clearly so users know whether to fork or open issues.

### Changed

- README footer now links the `LICENSE` file rather than just stating "MIT"

### Notes

This release is purely additive — no behavior, skill, or library changes. Versioned 3.3.1 as a patch.

If you maintain a fork: this is a good time to update your fork's LICENSE if you've made substantial changes, and to point your fork's README at your own `SECURITY.md` rather than mine.

---

## v3.3.0 — 2026-04-30

The "first impression" release. The plugin's value-prop now reads in 30 seconds, the quickstart is five copy-pasteable commands, and a SessionStart hook tells you what to run when you land in a fresh SFDX project. Same surface as v3.2; better discovery.

### Added — first-run experience

- **`hooks/session-start.sh`** — `SessionStart` hook that fires once per session. When `CLAUDE_PROJECT_DIR/sfdx-project.json` exists but `.claude/sf-project.json` doesn't, it emits a one-paragraph nudge pointing at `/argo:sf-init` (with surface-aware extras when React sources or AgentDefinitions are detected). Silent in every other case — never adds noise to projects that don't need it. Disable per-session via `ARGO_SESSION_NUDGE=0`.
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
/plugin marketplace update argo
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
- **`hooks/security-guard.sh`** — `PreToolUse` hook on `Bash`. Defense-in-depth wrapper around raw `sf` commands that bypass the library helpers. Disable per-session via `ARGO_SECURITY_GUARD=0` (testing only)
- **`docs/security-model.md`** — full security-model documentation: invariants, wire protocol, exit codes, JSON event shape, consent UX, threat model, recommended posture
- **Org-classification cache** at `${CLAUDE_PLUGIN_DATA}/argo/org-cache/<alias>.json`
- **Consent log** at `${CLAUDE_PLUGIN_DATA}/argo/consent-log/<project>.jsonl` — every override granted, with timestamp, skill, action, scope

### Added — config schema

- `security.prodOrgAliases` — aliases the plugin refuses to contact, ever (no override)
- `security.knownNonSandboxNonProd` — non-sandbox orgs classified as OK (dev orgs, demo orgs)
- `security.metadataOnly` (default `true`) — SOQL must target the metadata allowlist; otherwise per-call consent
- `security.allowAnonymousApex` (default `false`) — `sf apex run` is refused outright when false

### Added — wire protocol

When a security check refuses, the function emits a JSON event on stderr and exits with one of:

- `77` — consent required (overridable). Assistant presents to user; on grant, re-invokes with `ARGO_CONSENT_GRANTED=once` (single-use token)
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

1. Pull v3.2: `/plugin marketplace update argo`
2. Re-run `/argo:sf-init update` (or the full bootstrap) to populate the new `security` block. Required: classify every non-sandbox alias as either prod or known-non-prod
3. (Recommended) Run `/argo:sf-init verify` to confirm the new boundary holds against your config
4. Existing skills continue to work with no changes — the security library refuses what it must; data-touching skills surface consent prompts at runtime
5. CI: ensure `ARGO_CONSENT_GRANTED` is **never set** in the env. CI cannot grant consent; runs that would prompt instead fail loudly

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
- **`/agent-discover`** — fixed an outdated reference: the Agent Registry is populated by `/argo:mcp-bridge --register`, not `/argo:mcp-setup`

### Changed — template doc indexes

- `templates/docs/README.md` — generic patterns range now `SF-1..20` (was `SF-1..14`); adds React + Agents component indexes; adds an ADR section
- `templates/CLAUDE.md` — pattern-pack list updated to enumerate all 10 full packs (was "8 stub packs ready to author")

### Changed — deprecated pack handling

- `templates/packs/einstein-agentforce/` — `pack.json` now declares `deprecated: true` + `supersededBy: agentforce` and nulls out `installs.patternsAppendTo`/`checklistAppendTo` so an accidental `add` no longer half-installs anything; `patterns.md` rewritten as a redirect to `agentforce` (no more `_TODO_` placeholders); version bumped 0.1.0 → 0.2.0 to mark the cleanup. Directory still kept for back-compat with installs pinned to the old name; will be removed in a future major

### Removed

- **`templates/packs/functions/`** — dropped entirely. Salesforce Functions is retired; the pack was a stub. Removed from `README.md`, `templates/CLAUDE.md`, and `docs/pack-format.md`'s example domain list. The `CHANGELOG` v2.0.0 historical entry is preserved verbatim
- The "8 stub packs" callout in `templates/CLAUDE.md` — superseded by the per-pack list above

### Migration from v3.0.x

1. Pull v3.1: `/plugin marketplace update argo`
2. Existing pack installs continue to work; no schema changes
3. (Optional) Install any of the seven newly-authored packs:
   ```text
   /argo:pattern-pack add change-data-capture
   /argo:pattern-pack add data-cloud
   ...
   ```
4. (Optional but recommended) If your project's `.claude/sf-project.json` was written before v3, re-run `/argo:sf-init update` to align with the v3 schema documented in the updated Step 3
5. If your project pinned the deprecated `einstein-agentforce` pack:
   ```text
   /argo:pattern-pack remove einstein-agentforce
   /argo:pattern-pack add agentforce
   ```
6. If your project pinned the dropped `functions` pack: remove it from `.claude/argo-packs.json` manually (the pack directory no longer ships)

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

1. Pull v3: `/plugin marketplace update argo`
2. (Recommended) Install Salesforce's MCP server: `/argo:mcp-setup --profile dev`
3. (Recommended) Re-run `/argo:sf-init update` to add the new config keys (`mcp.toolsets`, `platform.frontend`, `quality.agentEvalThreshold`, `paths.agentDefinitions` if you ship agents)
4. If you ship agents:
   - Replace `einstein-agentforce` pack: `/argo:pattern-pack remove einstein-agentforce && /argo:pattern-pack add agentforce`
   - Run `/argo:agent-discover` to inventory existing agents
   - Run `/argo:trust-layer-audit` against any active agent
5. If you adopt React: `platform.frontend = "react"` (or `"both"`), then `/argo:sf-init` re-copies the standards docs
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
1. Pull the new plugin version: `/plugin marketplace update argo`
2. Re-run `/argo:sf-init update` to pick up the auto-detect for fields you didn't set in v1
3. (Optional) Run `/argo:org-explore` to populate the org cache for `@architect`
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
