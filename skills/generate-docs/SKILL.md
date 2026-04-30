---
name: generate-docs
description: Generate or update documentation for LWC components, Apex classes, React-on-Salesforce components, and Agentforce agents following the project's scoping rules. Audits existing docs for staleness.
data-access: none
---

You are generating documentation for this Salesforce project. Follow strict scoping rules driven by `.claude/sf-project.json`.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
LWC_PREFIX="$(sf_config_get '.naming.lwc.prefix // ""' "$ENV")"
LWC_EXCLUDES_JSON="$(sf_config_get '.naming.lwc.excludePrefixes // []' "$ENV")"
TEST_SUFFIX="$(sf_config_get '.naming.apex.testSuffix // "Test"' "$ENV")"
LWC_SRC="$(sf_config_get '.paths.lwcSource' "$ENV")"
APEX_SRC="$(sf_config_get '.paths.apexSource' "$ENV")"
LWC_DOCS="$(sf_config_get '.paths.lwcDocs' "$ENV")"
APEX_DOCS="$(sf_config_get '.paths.apexDocs' "$ENV")"
FRONTEND="$(sf_config_get '.platform.frontend // "lwc"' "$ENV")"
REACT_SRC="$(sf_config_get '.paths.reactSource // ""' "$ENV")"
REACT_DOCS="$(sf_config_get '.paths.reactDocs // ""' "$ENV")"
REACT_PREFIX="$(sf_config_get '.naming.react.prefix // ""' "$ENV")"
AGENT_DIR="$(sf_config_get '.paths.agentDefinitions // ""' "$ENV")"
AGENT_DOCS="$(sf_config_get '.paths.agentDocs // ""' "$ENV")"
```

Surfaces are gated by config: `react` paths only when `platform.frontend ∈ {"react", "both"}`; `agent` paths only when `paths.agentDefinitions` is set.

## Input

`$ARGUMENTS`:

Targets:
- `<lwc-name>` — generate or update its doc (auto-detected by directory in `paths.lwcSource`)
- `<ApexClassName>` — generate or update its doc
- `react <ComponentName>` — generate or update a React-component doc (when react is in scope)
- `agent <AgentName>` — generate or update an Agentforce agent doc (when agents are in scope)
- `all` — generate or update docs for every in-scope surface (LWC + Apex + React + agents, gated by config)
- `audit` — check all existing docs for staleness against current source code
- (empty) — prompt the user to specify what to document

CI flags (per `${CLAUDE_PLUGIN_ROOT}/docs/ci-output-contract.md`):
- `--ci` — machine-readable output, exit codes per contract
- `--format json|sarif` — output format (default `json` in CI mode)
- `--out <path>` — write to file instead of stdout
- `--fail-on error|warning|note` — minimum severity that triggers exit 1 (default `error`)
- `--env <name>` — read `.claude/sf-project.<name>.json` and merge over the base

## Scoping Rules

**LWC components** — only document components that:
- Live under `paths.lwcSource`
- Match `naming.lwc.prefix` (or all components if prefix is empty)
- Do **NOT** match any pattern in `naming.lwc.excludePrefixes`

**Apex classes** — only document production classes that:
- Are directly imported by an in-scope LWC component (`@salesforce/apex/<class>.<method>`) OR by an in-scope React component (`@salesforce/react/apex/<class>` or `@AuraEnabled` reachable from a `useApex` call)
- Are **NOT** test classes — skip anything ending in `naming.apex.testSuffix` (default: `Test`)

**Test classes** — do **NOT** create separate doc files for test classes. Reference the test class name in the production class doc's "Test Class" field instead.

**React components** — only document components that:
- Live under `paths.reactSource`
- Match `naming.react.prefix` if non-empty (PascalCase prefix on the component directory)
- Are not test files (`*.test.tsx` / `*.test.jsx` / `__tests__/`)

**Agentforce agents** — only document agents that:
- Have an `AgentDefinition` directory under `paths.agentDefinitions`
- Are explicitly project-owned (skip subdirectories that come from a managed package — detect via `.../installedPackages/` path or `<namespace>__` in the developer name)

## Steps

### For a specific target:

1. **Read the source code** thoroughly:
   - LWC: all `.js`, `.html`, `.css`, `.js-meta.xml` in the bundle
   - Apex: the `.cls` file
   - React: all `.tsx`/`.jsx`/`.ts`/`.js` (excluding tests) in the bundle, plus the meta XML
   - Agent: `<AgentName>.botDefinition-meta.xml`, `<AgentName>.botVersion-meta.xml`, `topics/*.topic-meta.xml`, `actions/*.action-meta.xml`, `subAgents/*.subAgent-meta.xml`
2. **Read existing documentation** in the matching docs directory if it exists
3. **Read the doc format** from a nearby existing doc file in the same directory to match style
4. **Generate or update** the doc file following the established format
5. **Update the index** (`<docsDir>/README.md`) if this is a new entry
6. **Update the root index** (`docs/README.md`) if this is a new entry

### For `all`:

1. **Discover in-scope LWC components**: directories under `paths.lwcSource` matching `naming.lwc.prefix*` (or all directories if prefix empty), excluding `naming.lwc.excludePrefixes`
2. **Discover in-scope Apex classes**: grep all in-scope LWC and React JS files for Apex imports; extract class names; exclude test classes by `naming.apex.testSuffix`
3. **Discover in-scope React components** (when react is in scope): directories under `paths.reactSource` matching `naming.react.prefix*` (PascalCase) or all when prefix empty
4. **Discover in-scope agents** (when agents are in scope): directories under `paths.agentDefinitions` containing a `*.botDefinition-meta.xml` file, excluding managed-package agents
5. **For each**, run the single-target steps above
6. **Report summary**: surfaces documented per kind, new entries added to indexes, time elapsed

### For `audit`:

1. **List all existing doc files** in `paths.lwcDocs`, `paths.apexDocs`, `paths.reactDocs`, `paths.agentDocs`
2. **Compare each doc** against its current source code
3. **Flag stale docs**: docs that don't match the current source (missing methods/topics/actions, wrong descriptions, outdated field/prop lists)
4. **Flag orphaned docs**: docs for components/classes/agents that no longer exist in source
5. **Flag missing docs**: in-scope surfaces without doc files
6. **Report** a summary table: name, kind, status (current/stale/orphaned/missing), and findings count
7. Audit mode is **read-only** — never modify files

## Documentation Format

Follow the existing format in each docs directory. Reference:
- **SF-12: Apex Inline Documentation** for Apex documentation standards
- **SF-13: LWC Inline Documentation** for LWC documentation standards
- **RX-* (react pack)** when documenting React components — bundle layout, props table, GraphQL queries used, i18n keys
- **AGT-* (agentforce pack)** when documenting agents — topics table, actions table, sub-agents, eval-suite location, escalation paths

## CI Mode

In CI mode (`--ci`), produce findings in the internal shape (see `docs/ci-output-contract.md`) instead of the Markdown report. Used primarily by `audit` mode in PR pipelines.

```json
[
  {
    "ruleId": "DOCS-STALE",
    "severity": "warning",
    "message": "Doc references method 'fetchOrders' which no longer exists in OrderController.cls",
    "file": "docs/apex-classes/OrderController.md",
    "line": 14,
    "tool": "generate-docs"
  }
]
```

For SARIF output, source `${CLAUDE_PLUGIN_ROOT}/hooks/lib/sarif.sh` and pipe through `sarif_emit "sf-dev-kit/generate-docs" "<plugin-version>"`.

Rule IDs:
- `DOCS-MISSING` — in-scope surface has no doc file (severity: note)
- `DOCS-STALE` — doc references a method/prop/topic/action no longer in source (severity: warning)
- `DOCS-ORPHANED` — doc exists for a surface that's no longer in source (severity: warning)
- `DOCS-INDEX-DRIFT` — index README is missing an entry that has its own doc (severity: note)

Exit codes (per contract):
- 0 — no findings at or above `--fail-on` threshold (or generation succeeded for non-audit modes)
- 1 — findings at or above the threshold
- 2 — invocation error (config missing, target not found)

## Rules

- Follow the scoping rules strictly — do not document out-of-scope surfaces
- Match the style of existing doc files in the same directory
- Always update the README index files when adding new entries
- When updating an existing doc, preserve any manually-added notes or context (look for `<!-- manual:keep -->` blocks; never drop content inside them)
- For `audit` mode, only report findings — do not modify any files
- **Don't document managed-package surfaces.** Skip anything in `installedPackages/` or with a `<namespace>__` prefix; those are owned by their package author
- **Agent docs reference the eval suite location.** The agent doc points to `tests/agent-evals/<agent-name>/` so reviewers can find the eval cases without grep
