---
name: sf-init
description: Bootstrap or update a Salesforce project for the sf-dev-kit AI workflow — auto-detects existing SFDX state, prompts for project values, writes .claude/sf-project.json (with optional per-env overrides), and scaffolds project-context, project-patterns, standards docs, and CLAUDE.md from the plugin's bundled templates
---

You are bootstrapping a Salesforce project for the AI workflow defined in the **`sf-dev-kit`** Claude Code plugin. Your job is to gather project-specific values from the user, write `.claude/sf-project.json` (and optional per-environment overrides), and scaffold supporting documentation by copying templates from the plugin's `templates/` directory.

## When to Use

- Setting up a brand-new Salesforce project (no `.claude/sf-project.json` exists) — full interactive bootstrap
- Re-scaffolding the workflow into an existing project that hasn't used it before
- Updating just a few fields after a change in naming convention, target org, or paths — see **Update-only mode** below
- Adding a new environment override (`dev`, `qa`, `uat`, `prod`)

## Plugin Path

Templates live in this plugin under `${CLAUDE_PLUGIN_ROOT}/templates/`. Use that env var when copying files. If `${CLAUDE_PLUGIN_ROOT}` is not set in your shell, ask the user where the plugin was installed and use that path.

## Input

The user provided: `$ARGUMENTS`

Argument forms:
- (empty) — full interactive bootstrap
- `update <field-path>...` — update-only mode; re-prompt for the named fields only (e.g., `update platform.defaultTargetOrg quality.codeCoverageTarget`)
- `env <name>` — scaffold/update a per-environment override (e.g., `env prod`); only prompts for keys the user wants to override
- `auto` — accept all auto-detected defaults without prompting (still asks for project name and description)

---

## Steps

### 0. Auto-detect existing project state (always)

Before prompting, scan the working directory and pre-fill defaults from what's already there. Report what was detected so the user can accept the auto-defaults.

| Source | Field |
|--------|-------|
| `sfdx-project.json` → `sourceApiVersion` | `platform.apiVersion` |
| `sfdx-project.json` → `packageDirectories[].path` (first one) | `paths.lwcSource = <path>/main/default/lwc`, `paths.apexSource = <path>/main/default/classes` |
| Most-common prefix in `{paths.lwcSource}/*/` directory names | `naming.lwc.prefix` (lowercase letters before the first uppercase letter — e.g., `acmeFoo` → `acme`) |
| `package.json` → presence of `lint` and `test:unit` scripts | `quality.lintCommand`, `quality.unitTestCommand` |
| `sf org list --json` → first non-scratch alias, or any DevHub | `platform.defaultTargetOrg` |

Run these checks via Bash, capture results, and present them to the user as a one-screen summary like:

```
Detected:
  apiVersion         66.0    (from sfdx-project.json)
  lwcSource          force-app/main/default/lwc
  apexSource         force-app/main/default/classes
  lwc.prefix         acme    (most common prefix in lwc/, 14 of 18 components)
  defaultTargetOrg   MyDev   (from `sf org list`)
  lintCommand        npm run lint
  unitTestCommand    npm run test:unit

Press enter to accept all detected values, or specify any to override.
```

Cache the detected values in a temporary variable; the prompts in step 2 use them as defaults.

### 1. Detect existing sf-dev-kit state

Check whether each of these exists in the user's project:
- `.claude/sf-project.json` (and any `.claude/sf-project.<env>.json` env overrides)
- `docs/project-context.md`
- `docs/patterns/salesforce-patterns.md`
- `docs/patterns/project-patterns.md`
- `docs/apex-standards.md`
- `docs/lwc-standards.md`
- `docs/quality-checklist.md`
- `CLAUDE.md`

Ask which files to (re)generate. Default to non-destructive — only overwrite files the user explicitly approves.

### 2. Gather project config values

Ask the user for each value below. Show defaults from step 0's auto-detection where applicable; otherwise use the static defaults shown. Empty replies accept the default.

#### Project identity
- `project.name` — display name (e.g., `My Salesforce Project`)
- `project.description` — one-sentence description

#### Naming
- `naming.lwc.prefix` — LWC name prefix (auto-detected from existing components if any). **Empty string is valid** — confirm explicitly if the user enters empty
- `naming.lwc.excludePrefixes` — array of prefixes to exclude from documentation/code-review batch modes. Default `[]`
- `naming.apex.{controller,service,batchable,schedulable,queueable,triggerHandler,test}Suffix` — defaults `Controller`, `Service`, `Batchable`, `Schedulable`, `Queueable`, `TriggerHandler`, `Test`

#### Platform
- `platform.apiVersion` — auto-detected from `sfdx-project.json`; default `66.0`
- `platform.defaultTargetOrg` — auto-detected via `sf org list`; default `default`. **Validate** by running `sf org list --json` and confirming the alias exists. If not, warn the user and offer to either pick from the available orgs or proceed anyway
- `platform.lwcTargets` — defaults:
  - For Experience Cloud: `["lightningCommunity__Page", "lightningCommunity__Default"]`
  - For Lightning Experience: `["lightning__AppPage", "lightning__RecordPage", "lightning__HomePage"]`
  - For Lightning Out / mixed: ask for the explicit list
- `platform.sharingDefault` — default `with sharing`

#### Frontend choice (added in v2.4)
- `platform.frontend` — `"lwc"` (default), `"react"`, or `"both"`. Determines which standards docs are copied, whether `paths.reactSource` is required, and which subagents are referenced in CLAUDE.md
- `naming.react.prefix` — optional PascalCase prefix for React component names (only when frontend includes `react`)
- `paths.reactSource` — only used when frontend includes `react`; default `force-app/main/default/react`
- `paths.reactDocs` — only used when frontend includes `react`; default `docs/react`

#### Paths
Auto-detected from `sfdx-project.json` if present; otherwise the standard SFDX defaults:
- `paths.lwcSource` (default `force-app/main/default/lwc`)
- `paths.apexSource` (default `force-app/main/default/classes`)
- `paths.lwcDocs` (default `docs/lwc`)
- `paths.apexDocs` (default `docs/apex-classes`)
- `paths.reactSource` / `paths.reactDocs` (when `platform.frontend` includes `react`)
- `paths.agentDefinitions` (default `force-app/main/default/botDefinitions`; for projects shipping Agentforce agents)
- `paths.patternsSalesforceDoc` (default `docs/patterns/salesforce-patterns.md`)
- `paths.patternsProjectDoc` (default `docs/patterns/project-patterns.md`)
- `paths.projectContextDoc` (default `docs/project-context.md`)
- `paths.standardsDocs` (default `["docs/apex-standards.md", "docs/lwc-standards.md", "docs/quality-checklist.md"]`; if `platform.frontend` includes `react`, also `docs/react-standards.md`)

#### Quality
- `quality.codeCoverageTarget` — integer percentage; default `85`
- `quality.lintCommand` — auto-detected from `package.json`; default `npm run lint`
- `quality.unitTestCommand` — auto-detected from `package.json`; default `npm run test:unit`

### 3. Write `.claude/sf-project.json`

Assemble the gathered values into the JSON structure below and write the file. Pretty-print with 2-space indentation.

```json
{
  "project":  { "name": "...", "description": "..." },
  "naming":   { "lwc": { "prefix": "...", "excludePrefixes": [] },
                "apex": { "controllerSuffix": "Controller", "serviceSuffix": "Service",
                          "batchableSuffix": "Batchable", "schedulableSuffix": "Schedulable",
                          "queueableSuffix": "Queueable", "triggerHandlerSuffix": "TriggerHandler",
                          "testSuffix": "Test" } },
  "platform": { "apiVersion": "66.0", "defaultTargetOrg": "default",
                "lwcTargets": ["lightningCommunity__Page", "lightningCommunity__Default"],
                "sharingDefault": "with sharing" },
  "paths":    { "lwcSource": "force-app/main/default/lwc",
                "apexSource": "force-app/main/default/classes",
                "lwcDocs": "docs/lwc", "apexDocs": "docs/apex-classes",
                "patternsSalesforceDoc": "docs/patterns/salesforce-patterns.md",
                "patternsProjectDoc": "docs/patterns/project-patterns.md",
                "projectContextDoc": "docs/project-context.md",
                "standardsDocs": ["docs/apex-standards.md", "docs/lwc-standards.md", "docs/quality-checklist.md"] },
  "quality":  { "codeCoverageTarget": 85,
                "lintCommand": "npm run lint",
                "unitTestCommand": "npm run test:unit" }
}
```

### 4. Copy generic standards docs from the plugin

```bash
mkdir -p docs/patterns
cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/apex-standards.md"               docs/apex-standards.md
cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/lwc-standards.md"                docs/lwc-standards.md
cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/quality-checklist.md"            docs/quality-checklist.md
cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/patterns/salesforce-patterns.md" docs/patterns/salesforce-patterns.md
# When platform.frontend includes "react", also copy:
case "$FRONTEND" in
  *react*)
    cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/react-standards.md" docs/react-standards.md
    ;;
esac
```

If `paths.standardsDocs` or `paths.patternsSalesforceDoc` were customized, copy to those custom locations instead.

### 5. Scaffold project-specific docs from templates

```bash
cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/project-context.md"             docs/project-context.md
cp "${CLAUDE_PLUGIN_ROOT}/templates/docs/patterns/project-patterns.md"   docs/patterns/project-patterns.md
```

### 6. Scaffold doc index stubs (only if missing)

For each, copy if the destination doesn't already exist, then substitute `{{project.name}}` with the value from step 2:
- `docs/lwc/README.md` ← `${CLAUDE_PLUGIN_ROOT}/templates/docs/lwc/README.md`
- `docs/apex-classes/README.md` ← `${CLAUDE_PLUGIN_ROOT}/templates/docs/apex-classes/README.md`
- `docs/README.md` ← `${CLAUDE_PLUGIN_ROOT}/templates/docs/README.md`

### 7. (Optional) Update CLAUDE.md

```bash
cp "${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md" CLAUDE.md
```
Then edit it to replace `{{project.name}}` with the value from step 2.

### 8. Report results

Summarize what was created/updated. Recommend next steps:
- Fill in the `_TODO_` sections of `docs/project-context.md`
- Add project-specific patterns to `docs/patterns/project-patterns.md` as they emerge
- Run `/sf-dev-kit:code-review all` once a few components exist
- (Optional) Run `/sf-dev-kit:org-explore` to populate the org cache so `@architect` can ground designs in real org state

---

## Update-only mode (`update <field-path>...`)

When invoked as `update foo.bar baz.qux`:
1. Read the existing `.claude/sf-project.json`
2. For each named field path, prompt the user with the **current value** as the default
3. Write back the updated JSON, preserving every other field
4. Skip steps 4–7 (template copying) — update mode never touches docs
5. Report only the diffed fields

Example:
```
$ /sf-dev-kit:sf-init update platform.defaultTargetOrg quality.codeCoverageTarget
platform.defaultTargetOrg [DevVM]: ProdSandbox
quality.codeCoverageTarget [85]: 90
Updated: platform.defaultTargetOrg, quality.codeCoverageTarget
```

## Environment override mode (`env <name>`)

When invoked as `env prod` (or `dev`, `qa`, `uat`, etc.):
1. Read the existing base config
2. Prompt the user for **only the keys they want to override** (skip with empty/`-`)
3. Write the override file to `.claude/sf-project.<name>.json` containing only the overridden keys (deep-nested where needed)
4. Skip template copying

Example output for `env prod`:
```json
{
  "platform": {
    "defaultTargetOrg": "ProdProd",
    "lwcTargets": ["lightning__RecordPage"]
  },
  "quality": {
    "codeCoverageTarget": 90
  }
}
```

The base config plus the override is what skills like `/sf-dev-kit:deploy --env prod` will see (deep-merged via `${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh`).

---

## Rules

- **Be interactive in the default mode.** Walk the user through each section; don't write the file from defaults silently
- **`auto` mode skips prompts** for fields with auto-detected or default values, but still asks for `project.name` and `project.description`
- **Default to non-destructive.** If a file exists, ask before overwriting
- **Empty `naming.lwc.prefix` is valid.** Confirm explicitly if the user enters empty so they don't do it by accident
- **Validate the target-org alias.** If `platform.defaultTargetOrg` doesn't resolve in `sf org list`, warn and offer the actual list
- **Validate JSON before writing.** If you can't construct valid JSON, report the issue and ask for corrections
- **Don't write source code.** This skill only writes config and doc scaffolding — never `.cls`, `.js`, `.html`, or `.xml` source files
- **Always replace `{{project.name}}` placeholders** in copied templates after copying — agents don't expect literal `{{project.name}}` in production docs
