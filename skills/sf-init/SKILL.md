---
name: sf-init
description: Bootstrap or update a Salesforce project for the argo AI workflow. Detects existing SFDX state aggressively, presents a single review screen with confidence indicators, edits only what the user picks, writes `.claude/sf-project.json`, scaffolds standards/docs, then runs a smoke test to verify everything resolves. Modes: full bootstrap, `auto`, `update <fields>`, `env <name>`, `verify`.
data-access: metadata-only
---

You are bootstrapping a Salesforce project for the **`argo`** Claude Code plugin. The interaction model is **detect → review → edit → write → verify**: detection does the heavy lifting, the user only edits what's ambiguous or missing, and a smoke test catches misconfigurations before they break downstream skills.

## When to Use

- Setting up a brand-new Salesforce project (no `.claude/sf-project.json` exists) — full bootstrap
- Re-scaffolding the workflow into a project that hasn't used it before
- Updating named fields after a naming/path/org change — see **`update` mode**
- Adding a per-env override (`dev`, `qa`, `uat`, `prod`) — see **`env` mode**
- Running just the smoke check after a manual edit — see **`verify` mode**

## Plugin Path

Templates live under `${CLAUDE_PLUGIN_ROOT}/templates/`. If `${CLAUDE_PLUGIN_ROOT}` isn't set, ask the user where the plugin was installed.

## Input

`$ARGUMENTS`:
- (empty) — full **detect → review → edit → write → verify** flow
- `auto` — accept all detected defaults; refuses if any ⚠️ required fields remain unfilled
- `update <field-path>...` — re-prompt for named fields only (e.g., `update platform.defaultTargetOrg quality.codeCoverageTarget`)
- `env <name>` — scaffold or update a per-env override at `.claude/sf-project.<name>.json`; review screen shows only override candidates
- `verify` — skip the bootstrap; just run the smoke test against the current config
- `--no-verify` — skip the smoke test step (CI escape hatch)
- `--ci` — non-interactive; outputs JSON; refuses to write if anything is ⚠️ required or if verify finds ❌

---

## The flow

### 1. Detect

Run all detectors via Bash; collect (value, confidence, evidence) per field. Confidence is one of `confident` / `ambiguous` / `default` / `required`.

| # | Field | Detection | Confident when | Ambiguous when | Notes |
|---|-------|-----------|----------------|-----------------|-------|
| 1 | `project.name` | `package.json.name` → `sfdx-project.json.namespace` → cwd basename | first source has a non-empty value | (n/a — has a fallback) | Always fillable |
| 2 | `project.description` | (none) | (n/a) | (n/a) | **Required** — flag ⚠️ |
| 3 | `platform.frontend` | `paths.reactSource` directory has `*.tsx`/`*.jsx` files? Bot definitions present? | one signal | both LWC and React sources present with non-trivial code | Default `lwc` if no signal |
| 4 | `platform.apiVersion` | `sfdx-project.json.sourceApiVersion` | present | (n/a) | Cross-check vs. `sf org display --json`; warn if 2+ versions behind |
| 5 | `platform.defaultTargetOrg` | `sf org list --json` non-scratch | exactly one non-scratch alias | multiple non-scratch aliases | ⚠️ if zero |
| 6 | `platform.lwcTargets` | union of `<targets>` across `*.js-meta.xml` | ≥1 LWC component, single distinct target set | multiple distinct target sets | Default Experience-Cloud bundle if no LWCs |
| 7 | `platform.sharingDefault` | majority sharing keyword across `.cls` files | majority ≥70% | mixed close to 50/50 | Default `with sharing` if no Apex |
| 8 | `naming.lwc.prefix` | most common letter-prefix in `{paths.lwcSource}/*/` | one prefix matches ≥70% | top prefix <70% | Empty string is valid (no convention) |
| 9 | `naming.lwc.excludePrefixes` | (none) | always `[]` | (n/a) | |
| 10 | `naming.react.prefix` | (none) | (n/a) | (n/a) | Default `""`; only included when react is in scope |
| 11 | `naming.apex.testSuffix` | most common suffix on classes ending in a test marker (`Test` / `Tests` / `_Test`) | majority ≥70% | mixed | Default `Test` |
| 12 | `paths.lwcSource` | `sfdx-project.json.packageDirectories[].path + "/main/default/lwc"` | exactly one PD | multiple PDs | |
| 13 | `paths.apexSource` | (same source) + `"/main/default/classes"` | exactly one PD | multiple PDs | |
| 14 | `paths.reactSource` | (same source) + `"/main/default/react"`; check directory exists | dir exists with files | dir absent but `frontend ∈ {react, both}` | Only when react in scope |
| 15 | `paths.agentDefinitions` | scan `force-app/**` for `*.botDefinition-meta.xml` | found | (n/a) | Skipped if no agents detected |
| 16 | `paths.agentDocs` | (none) | always default `docs/agents` | (n/a) | Only when agents in scope |
| 17 | `quality.codeCoverageTarget` | (none) | always default `85` | (n/a) | Mark "default — no signal" |
| 18 | `quality.agentEvalThreshold` | (none) | always default `0.85` | (n/a) | Only when agents in scope |
| 19 | `quality.lintCommand` | `package.json.scripts.lint` | present | (n/a) | Default `npm run lint` |
| 20 | `quality.unitTestCommand` | `package.json.scripts["test:unit"]` then `.test` | present | (n/a) | Default `npm run test:unit` |
| 21 | `notifications` | (none) | always omitted | (n/a) | Asked only if user opts in via `edit notifications` |
| 22 | `security.prodOrgAliases` | (none — user must classify) | (n/a) | (n/a) | **Required** if any non-sandbox alias is detected. The plugin refuses unknown non-sandbox orgs at runtime |
| 23 | `security.knownNonSandboxNonProd` | (none) | always `[]` | (n/a) | Dev/demo orgs that are non-sandbox but explicitly OK to contact |
| 24 | `security.allowAnonymousApex` | (none) | always `false` | (n/a) | When false (default), `sf apex run` is refused outright |

For each non-scratch alias from `sf org list --json`, run `sf org display --target-org <alias> --json` once during detection to capture `isSandbox` and cache the classification under `${CLAUDE_PLUGIN_DATA}/argo/org-cache/<alias>.json`. Aliases reporting `isSandbox: false` AND not yet listed in `security.prodOrgAliases` or `security.knownNonSandboxNonProd` surface on the review screen as ⚠️ required — the user must classify them before the write proceeds.

Detection is read-only. It produces a struct: each field has `{value, confidence, evidence}`.

### 2. Detect existing argo state

Check whether each of these already exists:
- `.claude/sf-project.json` (and any `.claude/sf-project.<env>.json`)
- `docs/project-context.md`
- `docs/patterns/{salesforce,project}-patterns.md`
- `docs/{apex,lwc,react}-standards.md`
- `docs/quality-checklist.md`
- `CLAUDE.md`

Report counts; ask permission to overwrite at the **end** of the review-and-edit step (one batch question), not now. Default: never overwrite without consent.

### 3. Render the review screen

One Markdown table-like block. Width-bounded. Each row: `N. field-path  value  marker  reason`. Markers:

- `✓` — confident detection
- `⚠️` — ambiguous (multiple candidates, weak signal, or "default — no signal")
- `⚠️ required` — must be filled before writing
- `(skipped)` — surface not in scope (e.g., agent paths when no agents detected)

Counts in the header tell the user at a glance how much to read:

```
[Detection complete — 13 of 17 fields filled, 2 need you, 2 need confirmation]

  1. project.name              acme-portal                     ✓ from package.json
  2. project.description       (none)                           ⚠️ required — what is this project for?
  3. platform.frontend         lwc                              ✓ no react sources detected
  4. platform.apiVersion       66.0                             ✓ from sfdx-project.json
  5. platform.defaultTargetOrg DevVM                            ⚠️ 3 non-scratch orgs available — confirm
  6. platform.lwcTargets       lightningCommunity__Page,
                               lightningCommunity__Default      ✓ inferred from 14 LWCs
  7. platform.sharingDefault   with sharing                     ✓ 18/22 Apex classes
  8. naming.lwc.prefix         acme                             ✓ 14/18 components match
  9. paths.lwcSource           force-app/main/default/lwc       ✓
 10. paths.apexSource          force-app/main/default/classes   ✓
 11. paths.agentDefinitions    (skipped)                        ✓ no agents detected
 12. quality.codeCoverageTarget 85                              ⚠️ default — no signal
 13. quality.lintCommand       npm run lint                     ✓ from package.json
 14. quality.unitTestCommand   npm run test:unit                ✓ from package.json
 15. notifications             (none)                           (default; you can add later)
 16. security.prodOrgAliases   []                               ⚠️ required — 2 non-sandbox orgs detected: ProdProd, UAT-Sandbox
 17. security.allowAnonymousApex false                          ✓ default — anonymous Apex disabled

Reply with one of:
  • The description for #2 (a sentence) — I'll confirm #5, then write
  • "edit 5 8 12" — adjust those before writing
  • "? 7" — explain what field 7 is and how it's used
  • "ok" or "looks good" — write as-is (only if no ⚠️ required remain)
  • "auto" — accept everything detectable; same blocker on ⚠️ required
  • "cancel" — bail without writing
```

### 4. Edit loop

Parse the user's reply by trying matches in this order:

| Reply shape | Action |
|-------------|--------|
| `cancel` (case-insensitive) | Abort with no writes |
| `? <N>` (or `help <N>`) | Print the help blurb for field N from the table below; re-show review screen |
| `edit <N> [<M> ...]` | For each N in order, run the per-field micro-prompt (below); after all done, re-render review screen |
| `auto` / `ok` / `looks good` / empty | If no ⚠️ required remain → proceed to write. Else → list the unmet required fields and re-ask |
| Any other free-text **and** `project.description` is the sole ⚠️ required | Treat as the description; if any other ⚠️ required remain, fill description and re-render review screen for those |
| Anything else | "I didn't recognize that. Reply with edit/?/ok/auto/cancel or the description text." |

#### Per-field micro-prompt

For each field being edited, present:

```
[Editing #5: platform.defaultTargetOrg]

Current:    DevVM   (most-recently-used non-scratch from `sf org list`)
Available:  DevVM, QASandbox, ProdSandbox

Type the alias to use, "back" to keep current, or "?" for help.
> 
```

Validate against the field's rules (next section). On failure, re-prompt with the validator's message; do not advance.

For enum fields (`platform.frontend`, `platform.sharingDefault`) and multi-select fields (`platform.lwcTargets`), use the **AskUserQuestion** tool — buttons are unambiguous.

For the org alias, validate against `sf org list --json`; if user types an alias not in the list, show the list and re-prompt.

#### Field validators

| Field | Validation |
|-------|------------|
| `project.name` | non-empty |
| `project.description` | non-empty; ≥10 chars suggested but not enforced |
| `platform.frontend` | enum: `lwc` / `react` / `both` |
| `platform.apiVersion` | matches `^[0-9]+\.0$`; warn if `< 60.0` or `> <current platform release>` |
| `platform.defaultTargetOrg` | resolves in `sf org list --json` |
| `platform.lwcTargets` | each value matches a known LWC target identifier |
| `platform.sharingDefault` | enum: `with sharing` / `without sharing` / `inherited sharing` |
| `naming.lwc.prefix` | empty OR `^[a-z][a-z0-9]*$`; warn if existing components don't match |
| `naming.*.suffix` | `^[A-Za-z][A-Za-z0-9]*$` |
| `paths.*` | path is a single relative path (no `..`); warn if directory doesn't exist (offer to create at write time) |
| `quality.codeCoverageTarget` | integer 0–100; warn if `<75` |
| `quality.agentEvalThreshold` | float 0.0–1.0 |
| webhook URLs | `^https://hooks\.slack\.com/` (Slack) or `^https://[a-z0-9-]+\.webhook\.office\.com/` (Teams) |

### 5. Write `.claude/sf-project.json`

Only proceed when no ⚠️ required remain and the user has signaled to write (`ok` / `auto` / accepted via the description-first path).

Assemble the v3 schema; **omit** keys whose preconditions don't hold (don't write `null`).

```json
{
  "project":  { "name": "...", "description": "..." },
  "naming":   { "lwc":   { "prefix": "...", "excludePrefixes": [] },
                "react": { "prefix": "" },
                "apex":  { "controllerSuffix": "Controller", "serviceSuffix": "Service",
                           "batchableSuffix": "Batchable", "schedulableSuffix": "Schedulable",
                           "queueableSuffix": "Queueable", "triggerHandlerSuffix": "TriggerHandler",
                           "testSuffix": "Test" } },
  "platform": { "apiVersion": "66.0", "defaultTargetOrg": "default",
                "lwcTargets": ["lightningCommunity__Page", "lightningCommunity__Default"],
                "sharingDefault": "with sharing",
                "frontend": "lwc",
                "devHubAlias": "DevHub",
                "packageName": "" },
  "paths":    { "lwcSource":  "force-app/main/default/lwc",
                "apexSource": "force-app/main/default/classes",
                "lwcDocs":    "docs/lwc",
                "apexDocs":   "docs/apex-classes",
                "reactSource":      "force-app/main/default/react",
                "reactDocs":        "docs/react",
                "agentDefinitions": "force-app/main/default/botDefinitions",
                "agentDocs":        "docs/agents",
                "patternsSalesforceDoc": "docs/patterns/salesforce-patterns.md",
                "patternsProjectDoc":    "docs/patterns/project-patterns.md",
                "projectContextDoc":     "docs/project-context.md",
                "standardsDocs": ["docs/apex-standards.md", "docs/lwc-standards.md", "docs/quality-checklist.md"] },
  "quality":  { "codeCoverageTarget":  85,
                "agentEvalThreshold":  0.85,
                "lintCommand":         "npm run lint",
                "unitTestCommand":     "npm run test:unit" },
  "notifications": { "webhooks": { "slack": "...", "teams": "..." } },
  "security": { "prodOrgAliases": ["ProdProd", "UAT-Sandbox"],
                "knownNonSandboxNonProd": [],
                "allowAnonymousApex": false }
}
```

**Conditional keys (omit when condition is false):**
- `naming.react`, `paths.reactSource`, `paths.reactDocs` — only when `platform.frontend ∈ {"react", "both"}`
- `paths.agentDefinitions`, `paths.agentDocs`, `quality.agentEvalThreshold` — only when agents are in scope
- `paths.standardsDocs` — append `"docs/react-standards.md"` when react in scope
- `notifications` — write only if at least one webhook URL was provided
- `security` — **always written**. Defaults are restrictive (`allowAnonymousApex: false`; the metadata-only SOQL allowlist is always enforced in code, not via config). `prodOrgAliases` defaults to every detected non-sandbox alias the user didn't classify as `knownNonSandboxNonProd` — failing safe

### 6. Copy generic standards docs

```bash
mkdir -p docs/patterns
cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/apex-standards.md"               docs/apex-standards.md
cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/lwc-standards.md"                docs/lwc-standards.md
cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/quality-checklist.md"            docs/quality-checklist.md
cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/patterns/salesforce-patterns.md" docs/patterns/salesforce-patterns.md
case "$FRONTEND" in
  *react*) cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/react-standards.md" docs/react-standards.md ;;
esac
```

If `paths.standardsDocs` or `paths.patternsSalesforceDoc` were customized, copy to those custom locations instead.

### 7. Scaffold project-specific docs

```bash
cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/project-context.md"             docs/project-context.md
cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/patterns/project-patterns.md"   docs/patterns/project-patterns.md
```

### 8. Scaffold doc index stubs (only if missing)

For each, copy if the destination doesn't already exist, then substitute `{{project.name}}` with the actual project name:

- `docs/lwc/README.md` ← `${CLAUDE_PLUGIN_ROOT}/templates/docs/lwc/README.md`
- `docs/apex-classes/README.md` ← `${CLAUDE_PLUGIN_ROOT}/templates/docs/apex-classes/README.md`
- `docs/README.md` ← `${CLAUDE_PLUGIN_ROOT}/templates/docs/README.md`

When `platform.frontend ∈ {"react", "both"}`:
- `docs/react/README.md` ← `${CLAUDE_PLUGIN_ROOT}/templates/docs/react/README.md`

When `paths.agentDefinitions` is set:
- `docs/agents/README.md` ← `${CLAUDE_PLUGIN_ROOT}/templates/docs/agents/README.md`

### 9. (Optional) Update CLAUDE.md

```bash
cp "${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md" CLAUDE.md
```

Then substitute `{{project.name}}` with the value from step 5. Other `{paths.*}`, `{platform.*}` references are intentional **runtime** placeholders — leave them; agents resolve them per request.

### 10. Verify (smoke test)

Skipped if `--no-verify`. Run all checks; render a checklist; record exit status.

| Check | Pass condition | Failure remediation hint |
|-------|----------------|--------------------------|
| Org alias resolves | `sf org display --target-org <alias> --json` exits 0 | Re-edit `platform.defaultTargetOrg` |
| `paths.lwcSource` exists | directory present | Create the directory or re-edit the path |
| `paths.apexSource` exists | directory present | Same |
| `paths.reactSource` exists (when react in scope) | directory present | Same — or change `platform.frontend` to `lwc` |
| `paths.agentDefinitions` exists (when in scope) | directory present | Same — or remove the path |
| API version compatible | within 2 versions of org's reported API | Edit `platform.apiVersion` to match the org |
| Lint command in scripts | `package.json.scripts[<lintCommand minus 'npm run '>]` present | Update `quality.lintCommand` or add the script |
| Unit test command in scripts | same shape | Same |
| Standards docs copied | each `paths.standardsDocs` exists | Re-run `/sf-init` (will detect existing config and just re-copy) |
| Doc indexes scaffolded | `lwc/README.md`, `apex-classes/README.md`, `docs/README.md`, conditional `react/`/`agents/` | Same |
| All non-sandbox orgs classified | every alias from `sf org list` is either in `security.prodOrgAliases` or `security.knownNonSandboxNonProd` (sandboxes skipped) | Edit one of those lists; an unclassified non-sandbox is refused at runtime |
| Security defaults intact | `security.allowAnonymousApex = false` (the metadata-only SOQL allowlist is always enforced) | Warns if anonymous Apex is loosened; does not fail (loosening is the user's decision) |
| `defaultTargetOrg` not in prod list | `platform.defaultTargetOrg` ∉ `security.prodOrgAliases` | Refuses all skill operations otherwise; pick a sandbox/scratch alias as the default |

Output:

```
[Verify]

✅ Org alias DevVM resolves
✅ paths.lwcSource exists
✅ paths.apexSource exists
✅ API version 66.0 within range
✅ Lint command found
✅ Unit test command found
✅ Standards docs copied
✅ Doc indexes scaffolded

8 passed, 0 failed. Config is healthy.
```

If any ❌:
```
✅ Org alias DevVM resolves
❌ paths.reactSource not found            (force-app/main/default/react missing — frontend is "react")
   Fix: create the directory, or run `/argo:sf-init update paths.reactSource`,
        or change frontend back to "lwc" via `/argo:sf-init update platform.frontend`
…

7 passed, 1 failed, 0 skipped. Config written but won't work end-to-end until fixed.
```

Exit codes (interactive: report only; CI mode: real exits):
- 0 — verify all-pass (or warnings only)
- 1 — verify found a ❌
- 2 — bootstrap aborted before write

### 11. Report results

After verify, summarize what was created/updated and recommend next steps:

- Fill in the `_TODO_` sections of `docs/project-context.md`
- Add project-specific patterns to `docs/patterns/project-patterns.md` as they emerge
- Run `/argo:org-explore` to populate the org cache so `@architect` can ground designs in real org state
- Run `/argo:code-review all` once a few components exist

---

## Mode-specific behavior

### `auto` mode

Skip the review screen UI entirely. Run detection, validate, and:
- If any ⚠️ required remain → exit 2 with a list of unfilled fields ("Re-run /sf-init to fill these interactively, or pass them via --field path=value")
- Else → write, copy, scaffold, verify
- Same exit codes as the interactive flow

### `update <field-path>...` mode

Skip the review screen entirely. For each named field path:
1. Read the current value from `.claude/sf-project.json`
2. Run the per-field micro-prompt with the current value as default
3. Apply the field validator
4. Write back the updated JSON, preserving every other key

Skip steps 6–9 (template copying). Run step 10 (verify) on the result; warn the user if their edit broke a previously-passing check.

### `env <name>` mode

1. Read the base config
2. Run detection in env-aware mode (e.g., look up `sf org list` for orgs that look env-shaped — `prod*`, `staging*`)
3. Render the review screen showing **only the fields likely to differ in this env** (org alias, coverage targets, agent eval threshold, webhooks). Pre-fill with the base value (visible in italics) plus any env-specific detected value.
4. Edit loop is the same
5. Write **only the keys the user actually changed** to `.claude/sf-project.<name>.json` (deep-nested; deep-merge over base when any skill is invoked with `--env <name>`)
6. Verify in env-merged mode

### `verify` mode

Skip everything except step 10. Read the current config (with `--env <name>` merge if passed), run all smoke checks, render the checklist, exit 0/1.

---

## Field help reference (used by `? <N>`)

A short blurb per field. When the user asks `? <N>`, print the matching blurb, then re-render the review screen.

- `project.name` — Display name of the project. Used in agent and skill output, doc headers, and the CLAUDE.md template
- `project.description` — One sentence on what the project does and who uses it. Surfaces in `@architect` output and PR-prep
- `platform.frontend` — Which UI framework(s) ship in this project. `lwc` (default), `react`, or `both`. Drives whether React-specific docs/skills are scoped in
- `platform.apiVersion` — API version stamped on every new metadata file. Higher = newer features; pin to one ≤ your default org's version
- `platform.defaultTargetOrg` — `sf` CLI alias for deploys, validations, test runs. For prod, use a per-env override (`sf-init env prod`) instead of changing this
- `platform.lwcTargets` — Default `<targets>` for new `.js-meta.xml` files. Experience Cloud uses `lightningCommunity__*`; Lightning Experience uses `lightning__*Page`
- `platform.sharingDefault` — Default sharing keyword for new Apex classes. Justify any deviation in code comments
- `naming.lwc.prefix` — Letter prefix on LWC component directory names. Empty string is valid (no convention)
- `naming.lwc.excludePrefixes` — Component prefixes to skip in batch operations (`code-review all`, `generate-docs all`)
- `naming.react.prefix` — PascalCase prefix on React component directory names; only used when react is in scope
- `naming.apex.*Suffix` — Class-name suffix conventions used by `@apex-dev` when scaffolding
- `paths.lwcSource` / `apexSource` / `reactSource` — Source roots agents read and write
- `paths.lwcDocs` / `apexDocs` / `reactDocs` / `agentDocs` — Doc roots `/generate-docs` writes into
- `paths.agentDefinitions` — Where Agentforce `*.botDefinition-meta.xml` lives. Default `force-app/main/default/botDefinitions`
- `quality.codeCoverageTarget` — Apex coverage threshold (0–100). `/test-coverage` and `/coverage-trend` enforce this
- `quality.agentEvalThreshold` — Agent eval pass threshold (0.0–1.0). Default `0.85` is the Trust Layer band
- `quality.lintCommand` / `unitTestCommand` — npm scripts the lint hook and `@qa` agent invoke
- `notifications.webhooks.{slack,teams}` — Outgoing webhook URLs for `/notify`. Slack: `https://hooks.slack.com/...`; Teams: `https://*.webhook.office.com/...`
- `security.prodOrgAliases` — Aliases the plugin must NEVER contact. Every `sf` invocation against these is refused unconditionally — no read, no metadata fetch, no validation. Detected via `sf org display --json` `isSandbox: false`; the user formalizes during `/sf-init`. Removing an alias from this list is a deliberate security decision
- `security.knownNonSandboxNonProd` — Non-sandbox orgs that are NOT production (developer orgs, demo orgs). Listed here, they're allowed; not listed AND non-sandbox, they're refused at runtime as "unclassified"
- *(There is no `metadataOnly` toggle — the metadata-only SOQL allowlist is **always** enforced in code.)* SOQL is restricted to a metadata allowlist (`ApexClass`, `EntityDefinition`, `Profile`, `Flow`, etc.); customer-data queries (`Account`, `Contact`, custom `__c`, `AgentSessionTrace`, etc.) require per-call user consent on every org. The full allowlist lives in `hooks/lib/security.sh` (`SEC_METADATA_OBJECTS`)
- `security.allowAnonymousApex` — When false (default), `sf apex run` is refused outright. When true, it's available but every invocation prompts for consent (anonymous Apex bypasses the metadata-only contract — it can read or write anything). Keep false in prod environments and CI

---

## Rules

- **Detect aggressively, ask sparingly.** Every field that has a deterministic source should be detected, not asked. The user only sees questions for what's genuinely ambiguous or opinion-shaped
- **One screen, then targeted edits.** Don't ask field-by-field unless the user asks for it via `edit N`. Confident users finish in one round-trip
- **Required ⚠️ blocks the write.** Empty `project.description` is the most common case; the writer refuses until it's set
- **Validators run inside edits.** A bad value never advances; the prompt re-fires with the validator's message
- **Verify after write.** The smoke test catches mistakes the review screen can't (e.g., a path that *was* valid at write time but has since been deleted). Always run unless `--no-verify`
- **Default to non-destructive.** If `.claude/sf-project.json` already exists, ask before overwriting. If `docs/*.md` already exist, ask before overwriting
- **Empty `naming.lwc.prefix` is valid.** Confirm explicitly so it's not a typo
- **Don't write source code.** This skill writes config + doc scaffolding; never `.cls`, `.js`, `.html`, or `.xml` source files
- **Always replace `{{project.name}}` placeholders.** `{paths.*}` and `{platform.*}` placeholders, by contrast, are runtime — leave them alone
- **In CI mode, every interactive prompt becomes a refusal.** CI must pass `auto` or per-field overrides on the command line; the skill never blocks waiting for input
- **Security defaults are restrictive.** `allowAnonymousApex: false` is written by default (and the metadata-only SOQL allowlist is always enforced in code, with no opt-out); loosening anonymous Apex prompts the user to confirm and is recorded in the consent log. Production aliases must be classified before the write completes — an unclassified non-sandbox alias is a ⚠️ required field
