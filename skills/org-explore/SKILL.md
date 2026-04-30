---
name: org-explore
description: Snapshot the target Salesforce org's schema (objects, fields, profiles, permission sets, installed packages) into a local cache for downstream sf-dev-kit skills. In MCP mode (Headless 360) this is optional — agents read live via the `data`/`metadata` toolsets. Cache is for offline use, batch reports, and snapshot-vs-snapshot diffs.
data-access: metadata-only
---

You are populating the **org cache** that downstream sf-dev-kit skills (especially `@architect`, `/sf-dev-kit:flow-audit`, `/sf-dev-kit:permset-audit`, `/sf-dev-kit:field-impact`) read for grounded design and analysis.

> **Headless 360 note**: with `@salesforce/mcp` configured (run `/sf-dev-kit:mcp-setup`), agents already see the live org via the `data` toolset. The cache is now **opt-in** — useful for offline work, deterministic reports, and historical comparisons. In MCP mode, `@architect` and friends read live by default; pass `--cache` to use a snapshot.

## Cache Location

```
${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugin-data}/sf-dev-kit/org-cache/<orgAlias>.json
```

Cache is per-org alias. A project may have several (dev / qa / prod), each cached separately. The cache file embeds a `_meta` block with timestamp and ttlSeconds so consumers can detect staleness.

## Read Project Config First

Source the helper and load merged config (with optional `--env`):

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/sf-cli.sh"
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/mcp.sh"
sf_cli_check || exit 2
```

`platform.defaultTargetOrg` is the target unless overridden.

## Routing — MCP-first, CLI fallback

When `mcp_prefer` returns true (i.e. `@salesforce/mcp` is reachable and `mcp.toolsets` includes `data`/`metadata`), this skill calls the MCP server's `data` toolset (`sobject-list`, `sobject-describe`, `soql-query`) instead of `sf` CLI subprocesses. The output shape of the cache file is identical either way.

Force CLI even when MCP is available: `--no-mcp`.
Force MCP and fail if unavailable: `--mcp`.

## Input

The user provided: `$ARGUMENTS`

Argument forms:
- (empty) — print live summary via MCP if available (`data` toolset); fall back to CLI summary; do NOT write cache
- `--cache` — produce a cache snapshot at the path below (legacy v1.3 behavior)
- `--target-org <alias>` — override the org alias (`-o` is also accepted)
- `--env <name>` — load `.claude/sf-project.<name>.json` overrides; defaultTargetOrg comes from the merged config
- `--refresh` — force refresh of an existing cache
- `--all-objects` — describe every sObject (slow; default is "custom + standard objects referenced in source")
- `--ttl <seconds>` — override the freshness TTL (default 86400 = 24h)
- `--no-mcp` — force CLI path even if `@salesforce/mcp` is configured
- `--mcp` — require MCP path; exit 2 if not available
- `--ci` — exit non-zero with no human-readable noise; emit a one-line JSON summary

> **Default behavior changed in v2.1 (Phase 13)**: bare `org-explore` no longer writes a cache. Use `--cache` to opt in. This avoids stale-cache surprises when an agent has live access via MCP.

## Steps

### 1. Resolve org alias
```bash
ORG="$(sf_config_get '.platform.defaultTargetOrg' "$ENV")"
[[ -n "$TARGET_OVERRIDE" ]] && ORG="$TARGET_OVERRIDE"
sf_cli_alias_exists "$ORG" || { echo "[org-explore] Org alias '$ORG' not found in `sf org list`" >&2; exit 2; }
```

### 2. Check cache freshness
```bash
CACHE_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugin-data}/sf-dev-kit/org-cache"
CACHE_FILE="$CACHE_DIR/$ORG.json"
mkdir -p "$CACHE_DIR"
TTL="${TTL:-86400}"
```
If `$CACHE_FILE` exists and `(now - _meta.cachedAt) < TTL` and not `--refresh`, exit 0 with "cache fresh" message.

### 3. Discover in-scope objects (unless `--all-objects`)
- Custom: query `sf sobject list --target-org $ORG --sobject custom --json`
- Standard objects referenced in source: grep the apex source dir for `Account|Contact|Case|Lead|Opportunity|User|...` — only describe those that actually appear

### 4. Describe each object
For each object in scope, prefer MCP routing when available:
```bash
if mcp_prefer; then
  mcp_run data sobject-describe '{"sobject":"'"$obj"'","org":"'"$ORG"'"}'
else
  sf_cli_describe "$obj" "$ORG"
fi > /tmp/desc-$obj.json
```
Capture: API name, label, fields (api name, type, length, picklist values, custom flag, formula expression), child relationships, record-type info.

### 5. Query profiles, permission sets, package versions
```bash
sf_cli_query "SELECT Id, Name, UserType, IsCustom FROM Profile" "$ORG"
sf_cli_query "SELECT Id, Name, Label, License.Name FROM PermissionSet WHERE IsOwnedByProfile = false" "$ORG"
sf_cli_query "SELECT Id, MasterLabel, DeveloperName, IsActive FROM PermissionSetGroup" "$ORG"
sf_cli_query "SELECT Id, SubscriberPackage.Name, SubscriberPackage.NamespacePrefix, SubscriberPackageVersion.MajorVersion, SubscriberPackageVersion.MinorVersion, SubscriberPackageVersion.PatchVersion, SubscriberPackageVersion.BuildNumber FROM InstalledSubscriberPackageVersion" "$ORG"
```

### 6. Query active Flows (cheap; flow-audit will dig deeper)
```bash
sf_cli_query "SELECT DeveloperName, Label, ProcessType, TriggerType, ActiveVersion.VersionNumber FROM FlowDefinitionView WHERE IsActive = TRUE" "$ORG"
```

### 7. Assemble cache JSON

```json
{
  "_meta": {
    "orgAlias": "DevVM",
    "orgInstanceUrl": "https://...",
    "orgEdition": "Developer",
    "cachedAt": "2026-04-28T10:30:00Z",
    "ttlSeconds": 86400,
    "schemaVersion": 1,
    "scope": {
      "allObjects": false,
      "objectsCustom": 27,
      "objectsStandardReferencedInSource": 8
    }
  },
  "objects": [
    {
      "apiName": "Account",
      "label": "Account",
      "isCustom": false,
      "fields": [
        { "apiName": "Name", "label": "Account Name", "type": "string", "length": 255, "isCustom": false }
      ],
      "childRelationships": [],
      "recordTypes": []
    }
  ],
  "profiles": [],
  "permissionSets": [],
  "permissionSetGroups": [],
  "installedPackages": [],
  "activeFlows": []
}
```

Pretty-print with 2-space indentation. Write atomically (write to `$CACHE_FILE.tmp`, then `mv`).

### 8. Report

Default output:
```
[org-explore] Cached org 'DevVM' (Developer Edition)
  Objects:               27 custom + 8 standard
  Profiles:              17
  Permission sets:       43
  Permission set groups: 6
  Installed packages:    2
  Active flows:          12
  Cache:                 <CLAUDE_PLUGIN_DATA>/sf-dev-kit/org-cache/DevVM.json
  Fresh until:           2026-04-29T10:30:00Z (24h TTL)
```

CI mode (`--ci`): emit one line of JSON to stdout:
```json
{"org":"DevVM","cachedAt":"...","objects":35,"profiles":17,"permsets":43,"flows":12}
```

## Rules

- **Never write secrets to the cache.** The cache is for shape/metadata, not data. No record contents, no auth tokens.
- **Atomic writes.** Always write `<file>.tmp` then `mv` to avoid leaving a half-written cache that another skill might read mid-write.
- **Incremental discovery.** A custom org may have hundreds of sObjects; describing all of them takes minutes. Default to "custom + source-referenced standard"; `--all-objects` is opt-in.
- **Don't fail noisily on partial errors.** If a single sobject describe fails, log it to the cache `_meta.errors` array and continue.
- **Report stale-but-usable.** If consumers (`@architect`, etc.) detect a stale cache, they should still use it but note the timestamp in their output.

## Consumers

Skills and agents that read the cache:
- `@architect` — pre-design data-model verification
- `@data-architect` (Phase 3) — schema design
- `/sf-dev-kit:org-diff` — diff against this snapshot
- `/sf-dev-kit:permset-audit` — combine cache profiles/permsets with ObjectPermissions queries
- `/sf-dev-kit:field-impact` — verify field exists in target before searching source
- `/sf-dev-kit:flow-audit` — combine activeFlows summary with detailed run-history queries
