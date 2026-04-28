---
name: deploy
description: Deploy or validate Salesforce metadata against the project's default org (or another org if specified)
---

You are deploying Salesforce metadata for this project. Always read the project config first.

## Read Project Config

Start by reading `.claude/sf-project.json`:
- `platform.defaultTargetOrg` — the org alias to deploy to unless the user specifies otherwise
- `paths.lwcSource` — base directory for LWC component lookups
- `paths.apexSource` — base directory for Apex class lookups

## Input

The user provided: `$ARGUMENTS`

This could be:
- An LWC component name — deploy the component bundle and any Apex dependencies
- An Apex class name — deploy the Apex class plus its test class (if one exists)
- A file path — deploy that specific path
- The word `all` — deploy the full project
- The modifier `validate` or `--validate` — run validation only (dry-run, no actual deploy)
- An override `--target-org <alias>` — use a different org instead of `platform.defaultTargetOrg`
- Empty — prompt the user to specify what to deploy

## Steps

1. **Parse the input.** Determine what to deploy and whether it's a validation-only run.

2. **Resolve source paths.**
   - For LWC component names: `{paths.lwcSource}/{componentName}/`
     - Also find Apex dependencies by grepping the JS file for `@salesforce/apex/` imports
   - For Apex class names: `{paths.apexSource}/{ClassName}.cls` + `{ClassName}.cls-meta.xml`
     - Also include the test class: `{ClassName}{naming.apex.testSuffix}.cls` + meta (if it exists). Default `testSuffix` is `Test`
   - For `all`: deploy the full `force-app` directory
   - Verify all resolved paths exist before deploying

3. **Build the deploy command.**
   - Substitute `{platform.defaultTargetOrg}` from config (or the user's override) for `<org>`:
   ```
   sf project deploy start --target-org <org> --source-dir {path1} --source-dir {path2} --wait 10
   ```
   - For validation only, add `--dry-run`:
   ```
   sf project deploy start --target-org <org> --source-dir {path1} --dry-run --wait 10
   ```
   - For `all`:
   ```
   sf project deploy start --target-org <org> --wait 10
   ```

4. **Run the deploy and report results.**
   - Show the command being run
   - Report success or failure
   - If failed, show the error details clearly
   - List which components were deployed/validated

## Rules

- **Default to `platform.defaultTargetOrg` from config** unless the user specifies a different org
- **Never deploy to production** without explicit user confirmation. If the user specifies an org alias that looks like production (e.g., `prod`, `production`, mentions a production username), ask for confirmation first
- Always verify source paths exist before running the deploy command
- If a component has Apex dependencies, include them in the deploy
- If deploying an Apex class, always include its test class if one exists (using `naming.apex.testSuffix` from config)
- Report results clearly: components deployed, status, any errors
