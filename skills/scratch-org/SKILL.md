---
name: scratch-org
description: Create or destroy a Salesforce scratch org from `config/project-scratch-def.json`, optionally deploy the project, optionally seed with the project's TestDataFactory. Useful for clean-slate testing, CI runs, and onboarding new developers.
---

You are creating or destroying a **scratch org** for the project. Scratch orgs are short-lived (max 30 days), feature-flag-controlled Salesforce instances tied to a Dev Hub. They're the right tool for CI tests, integration tests, and clean-slate dev work.

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
DEV_HUB="$(sf_config_get '.platform.devHubAlias // \"DevHub\"' "$ENV")"
DEFINITION="${SCRATCH_DEF:-config/project-scratch-def.json}"
```

If `platform.devHubAlias` is not set in `sf-project.json`, fall back to `DevHub`. Recommend adding it to the config for clarity.

## Input

`$ARGUMENTS`:
- `create [<alias>]` — create a scratch org with the given alias (default: timestamp-based)
- `destroy <alias>` — delete the named scratch org
- `list` — list scratch orgs the user owns
- `recreate <alias>` — destroy + create with the same alias
- `--days <n>` — duration (1–30, default 7)
- `--no-deploy` — create only, skip the source push (default: push)
- `--no-seed` — skip running TestDataFactory anonymous Apex (default: seed if a factory exists)
- `--definition <path>` — override the scratch def path
- `--ci` — machine output

## Steps

### `create [<alias>]`

1. **Verify Dev Hub** is logged in:
   ```bash
   sf_cli_alias_exists "$DEV_HUB" || { echo "[scratch-org] Dev Hub '$DEV_HUB' not authenticated. Run: sf org login web --alias $DEV_HUB --set-default-dev-hub" >&2; exit 2; }
   ```

2. **Verify scratch definition exists**:
   ```bash
   [[ -f "$DEFINITION" ]] || { echo "[scratch-org] Scratch definition not found: $DEFINITION" >&2; exit 2; }
   ```

3. **Generate alias if not provided**:
   ```bash
   ALIAS="${1:-$(printf 'scratch-%s' "$(date +%Y%m%d-%H%M%S)")}"
   ```

4. **Create the scratch org**:
   ```bash
   sf org create scratch \
     --target-dev-hub "$DEV_HUB" \
     --definition-file "$DEFINITION" \
     --alias "$ALIAS" \
     --duration-days "${DAYS:-7}" \
     --set-default \
     --json
   ```

5. **Push source** (unless `--no-deploy`):
   ```bash
   sf project deploy start --target-org "$ALIAS" --wait 30
   ```

6. **Seed test data** (unless `--no-seed`):
   - Check if `force-app/.../classes/TestDataFactory.cls` exists
   - If yes, run anon-Apex that calls a per-project `seed()` method (the factory should expose one). If the factory doesn't have a `seed()`, skip with a note
   ```bash
   sf apex run --target-org "$ALIAS" --file "${CLAUDE_PLUGIN_ROOT}/templates/scratch/seed.apex"
   ```
   The bundled `seed.apex` calls `TestDataFactory.seed();` if the method exists; the user is encouraged to define it.

7. **Seed agent test data** (unless `--no-seed-agents`, when the project has agents):
   - If `botDefinitions/` exists in source, also run the agent seed:
   ```bash
   sf apex run --target-org "$ALIAS" --file "${CLAUDE_PLUGIN_ROOT}/templates/scratch/seed-agents.apex"
   ```
   The bundled `seed-agents.apex` calls `TestDataFactory.seedAgents();` if defined. Agent eval suites typically need richer data (Cases with rich context, Orders with edge-case fields populated) than plain unit tests — define `seedAgents()` on your factory to make scratch-org eval runs representative.

7. **Open the org** (only in interactive mode, not `--ci`):
   ```bash
   sf org open --target-org "$ALIAS"
   ```

### `destroy <alias>`

```bash
sf org delete scratch --target-org "$alias" --no-prompt
```

Confirm the alias matches a scratch org (not a prod alias) before deleting.

### `list`

```bash
sf org list --json | jq '.result.scratchOrgs[] | {alias, expirationDate, status, instanceUrl}'
```

### `recreate <alias>`

`destroy <alias>` then `create <alias>` with the same flags.

## Output

Default Markdown:
```
# Scratch Org: scratch-20260428-141500

✅ Created via Dev Hub: DevHub (10.2s)
   Username:        test-xyz@example.com
   Instance URL:    https://....scratch.my.salesforce.com
   Expires:         2026-05-05 (7 days)
✅ Source deployed (62.4s) — 137 components
✅ Seed data inserted (3.1s) — 50 Accounts, 200 Contacts, 50 Orders

## Next steps
- Open: sf org open --target-org scratch-20260428-141500
- Run tests: /sf-dev-kit:test-coverage all --target-org scratch-20260428-141500
- Destroy: /sf-dev-kit:scratch-org destroy scratch-20260428-141500
```

CI mode: emit one JSON line per phase with timing.

## Bundled seed template

The plugin ships `templates/scratch/seed.apex` (created by Phase 7 commit). It's a 5-line wrapper that calls `TestDataFactory.seed()` if defined. Users override by adding their own `seed()` method to their factory.

## Exit codes
- 0 — operation succeeded
- 1 — partial success (e.g., create succeeded but deploy failed); the org exists, user should investigate
- 2 — invocation error (Dev Hub not auth, definition missing, etc.)

## Rules

- **Default duration is short.** 7 days, not 30. Long-lived scratches drift; if the user needs longer, they can pass `--days 30`
- **Prefix scratch alias with `scratch-`.** Makes it impossible to accidentally `destroy` a prod alias
- **Refuse to destroy non-scratch orgs.** Verify via `sf org list` that the alias is in `scratchOrgs[]`
- **Don't push to a scratch with `--no-deploy`.** The user explicitly opted out
- **Honor the project's `paths.apexSource`** when looking for `TestDataFactory` to seed
