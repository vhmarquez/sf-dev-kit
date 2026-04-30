---
name: package-version
description: Manage Salesforce 2GP / unlocked package versions — create, promote (release), and list versions. Wraps `sf package version create/promote/list` with conventions for changelog generation and release tagging.
data-access: metadata-only
---

You are managing **package versions** for a 2GP (Second-Generation Packaging) or unlocked package project. Use this skill when the project is distributed as a package (typical for ISVs, optional for internal SFDX projects).

## Read Project Config First

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/config.sh"
DEV_HUB="$(sf_config_get '.platform.devHubAlias // \"DevHub\"' "$ENV")"
PACKAGE="$(sf_config_get '.platform.packageName // empty' "$ENV")"
```

The package name comes from `sf-project.json` `platform.packageName` (you may need to add it). Or, if `sfdx-project.json` defines a `packageDirectories[*].package` entry, use that.

## Input

`$ARGUMENTS`:
- `create [--name <pkg>]` — build a new package version (a beta / installable)
- `promote <subscriberPackageVersionId>` — promote a beta to released (production-installable)
- `list` — list versions of the configured package
- `install <subscriberPackageVersionId> [--target-org <alias>]` — install a version into an org
- `--installation-key <key>` — for `create` / `install`; protects beta versions
- `--code-coverage` — verify code coverage during create (recommended)
- `--ci` — machine output

## Steps

### `create`

1. Verify Dev Hub auth:
   ```bash
   sf_cli_alias_exists "$DEV_HUB" || { echo "..." >&2; exit 2; }
   ```

2. Build:
   ```bash
   sf package version create \
     --target-dev-hub "$DEV_HUB" \
     --package "$PACKAGE" \
     ${KEY:+--installation-key "$KEY"} \
     ${CODE_COV:+--code-coverage} \
     --wait 30 \
     --json > /tmp/pkg-create.json
   ```

3. Capture the new `SubscriberPackageVersionId` (`04t...`) and the `PackageVersionId` (`05i...`) from the JSON.

4. Append to `${CLAUDE_PLUGIN_DATA}/argo/packages/<project>/versions.jsonl`:
   ```json
   {"createdAt":"...","subscriberId":"04t...","packageId":"05i...","versionNumber":"1.4.0.NEXT","released":false,"codeCoverage":89.2}
   ```

5. Optionally tag the git ref: `v1.4.0-beta.NEXT` (per `sfdx-project.json` versionNumber bump rules)

6. Emit installation URL the user can share for QA.

### `promote <id>`

```bash
sf package version promote --package "$id" --no-prompt --json
```

This converts a beta to released. Update `versions.jsonl` row's `released: true`. Tag the git ref `v1.4.0` (sans `-beta`).

### `list`

```bash
sf package version list --packages "$PACKAGE" --target-dev-hub "$DEV_HUB" --json
```

Format as a Markdown table: version number, subscriber id, released?, created date, code coverage.

### `install <id> [--target-org <alias>]`

```bash
sf package install --target-org "$ORG" --package "$id" ${KEY:+--installation-key "$KEY"} --no-prompt --wait 20 --json
```

## Output

Default Markdown for `create`:
```
# Package Version Created

Package:           Acme_Sales_Pkg
Version:           1.4.0-beta.7 (build #7)
Subscriber ID:     04t1b00000XYZ
Code coverage:     89.2% (above 75% required)
Created at:        2026-04-28T14:30:00Z

## Install URL
https://login.salesforce.com/packaging/installPackage.apexp?p0=04t1b00000XYZ

## Next steps
- Test install in a sandbox: /argo:package-version install 04t1b00000XYZ --target-org Sandbox
- Promote to released: /argo:package-version promote 04t1b00000XYZ
- (After release tag git: git tag v1.4.0)
```

## Exit codes
- 0 — succeeded
- 1 — failed (coverage too low, build failure, etc.)
- 2 — invocation error

## Rules

- **Always require `--code-coverage` on create.** Salesforce demands ≥75% on production package versions. Failing fast in beta is cheaper than failing at promote
- **Don't promote without a sandbox install test.** The skill prints a reminder; humans approve
- **Honor the 4-day quick-deploy window for non-package projects.** This skill is for *package* projects; non-package projects use `/diff-deploy` + `/quick-deploy`
- **Never delete versions.** Salesforce doesn't allow it for released versions; betas can be deprecated but not deleted

## Consumers

- ISV release pipeline: create → install in QA sandbox → run E2E → promote → install in pilot orgs
- `/release-notes` reads the latest released version's `versionNumber` for the release header
