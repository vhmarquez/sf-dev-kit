# Pattern Pack Format

A **pattern pack** is a self-contained directory under `templates/packs/<pack-name>/` that bundles patterns, agent extensions, quality-checklist additions, and optional skills for a specific Salesforce domain (Platform Events, Change Data Capture, Field Service, etc.).

## Why packs?

The base plugin ships generic SF-1..20 patterns and agents. Salesforce has many specialized surfaces (Industries, Field Service, Data Cloud, CDC, etc.) that not every project uses. Bundling them all into the base plugin would bloat installation; ignoring them leaves expert teams without scaffolding. Packs are opt-in modules: install only the ones your project uses.

## Directory layout

```
templates/packs/<pack-name>/
├── pack.json                 ← required; manifest
├── README.md                 ← user-facing overview, when to use
├── patterns.md               ← required; the pack's PEX-N or DOMAIN-N patterns
├── checklist.md              ← optional; additions appended to docs/quality-checklist.md
├── agents/                   ← optional; new or extending agents
│   └── <agent-name>.md
├── skills/                   ← optional; new skills
│   └── <skill-name>/SKILL.md
└── examples/                 ← optional; worked example source files
    └── ...
```

## `pack.json` manifest

```json
{
  "name": "platform-events",
  "displayName": "Platform Events",
  "description": "Patterns for publishing and subscribing to Salesforce Platform Events.",
  "version": "1.0.0",
  "patternsPrefix": "PE",
  "extends": [],
  "requires": {
    "sfApiVersion": "60.0",
    "edition": ["Developer", "Enterprise", "Performance", "Unlimited"]
  },
  "installs": {
    "patternsAppendTo": "patternsSalesforceDoc",
    "checklistAppendTo": "quality-checklist.md",
    "agents": ["agents/<filename>.md"],
    "skills": ["skills/<skill-name>/SKILL.md"]
  }
}
```

| Field | Purpose |
|-------|---------|
| `name` | The pack id used by `/pattern-pack add <name>` |
| `displayName` | Human-readable name |
| `description` | One-sentence overview |
| `version` | Semver of the pack |
| `patternsPrefix` | `PE`, `CDC`, `BIG`, `FN`, `FS`, `IND`, `CMS`, `AI`, `DC`, etc. — patterns inside numbered `<prefix>-N` |
| `extends` | Other packs this depends on (rare) |
| `requires` | Minimum API version, eligible org editions |
| `installs.patternsAppendTo` | Concatenates `patterns.md` to the configured patterns doc (default: `paths.patternsSalesforceDoc`) |
| `installs.checklistAppendTo` | Appends `checklist.md` to the project's `docs/quality-checklist.md` |
| `installs.agents` | List of agent files copied into the user's project's agents dir (rare; usually plugin-level) |
| `installs.skills` | List of skill dirs copied into the user's project's skills dir (rare; usually plugin-level) |

## Authoring rules

1. **One domain per pack.** Don't mix Platform Events with CDC; both are event-driven but the patterns differ
2. **Patterns numbered with the pack prefix.** `PE-1`, `PE-2` for platform-events; `CDC-1` for change-data-capture
3. **No SF-N collisions.** Pack patterns never use the `SF-` prefix; that's reserved for the base plugin
4. **Anti-patterns get their own section.** Each pattern has Rules; the pack's `patterns.md` ends with an "Anti-patterns" section listing common mistakes
5. **Worked example optional but recommended.** A small reference implementation in `examples/` makes the pack tangible
6. **Checklist additions are short.** Don't restate base checklist items; only the pack-specific ones (e.g., "Platform Event subscriber handles replay-id correctly")

## Install flow

`/sf-dev-kit:pattern-pack add <pack-name>`:
1. Reads `${CLAUDE_PLUGIN_ROOT}/templates/packs/<pack-name>/pack.json`
2. Verifies `requires.sfApiVersion` against `platform.apiVersion` from sf-project.json
3. Appends `patterns.md` to the project's patterns doc, with a header comment marking the source pack and version
4. Appends `checklist.md` to the project's quality-checklist.md if present
5. Copies any agent / skill files into the user's project under `.claude/agents/` and `.claude/skills/` (project-local; doesn't pollute the plugin)
6. Records the install in `.claude/sf-dev-kit-packs.json` so subsequent runs can detect already-installed packs

## Removal

`/sf-dev-kit:pattern-pack remove <pack-name>`:
- Walks the pack-installed sections (marked with `<!-- pack:<name> begin -->` / `<!-- pack:<name> end -->` in the appended files)
- Removes them
- Deletes the project-local agent/skill files from `.claude/`
- Updates `.claude/sf-dev-kit-packs.json`
