---
name: generate-docs
description: Generate or update documentation for LWC components and Apex classes following the project's scoping rules
---

You are generating documentation for this Salesforce project. Follow strict scoping rules driven by `.claude/sf-project.json`.

## Read Project Config First

Always start by reading `.claude/sf-project.json`:
- `naming.lwc.prefix` — components matching this prefix are in scope (empty string means all components)
- `naming.lwc.excludePrefixes` — components matching any of these prefixes are out of scope
- `naming.apex.testSuffix` — used to identify (and skip) test classes
- `paths.lwcSource`, `paths.apexSource` — source roots
- `paths.lwcDocs`, `paths.apexDocs` — documentation roots

## Input

The user provided: `$ARGUMENTS`

This could be:
- An LWC component name — generate or update its doc
- An Apex class name — generate or update its doc
- The word `all` — generate or update docs for all in-scope components and classes
- The word `audit` — check all existing docs for staleness against current source code
- Empty — prompt the user to specify what to document

## Scoping Rules

**LWC components** — only document components that:
- Match `naming.lwc.prefix` from config (or all components if prefix is empty)
- Do **NOT** match any pattern in `naming.lwc.excludePrefixes`

**Apex classes** — only document production classes that:
- Are directly imported by an in-scope LWC component (grep in-scope JS files for `@salesforce/apex/`)
- Are **NOT** test classes — skip anything ending in `naming.apex.testSuffix` (default: `Test`)

**Test classes** — do **NOT** create separate doc files for test classes. Reference the test class name in the production class doc's "Test Class" field instead.

## Steps

### For a specific component/class:

1. **Read the source code** thoroughly (all files for LWC: JS, HTML, CSS, meta XML; or the `.cls` for Apex)
2. **Read existing documentation** in `{paths.lwcDocs}` or `{paths.apexDocs}` if it exists
3. **Read the doc format** from a nearby existing doc file in the same directory to match style
4. **Generate or update** the doc file following the established format
5. **Update the index** (`{paths.lwcDocs}/README.md` or `{paths.apexDocs}/README.md`) if this is a new entry
6. **Update the root index** (`docs/README.md`) if this is a new entry

### For `all`:

1. **Discover in-scope LWC components**: List all directories in `{paths.lwcSource}` matching `{naming.lwc.prefix}*` (or all directories if prefix is empty), excluding any matching patterns in `naming.lwc.excludePrefixes`
2. **Discover in-scope Apex classes**: Grep all in-scope LWC JS files for `@salesforce/apex/` imports, extract class names, exclude any ending in `naming.apex.testSuffix`
3. **For each**, run the single-component steps above
4. **Report summary**: components documented, classes documented, any new entries added to indices

### For `audit`:

1. **List all existing doc files** in `{paths.lwcDocs}` and `{paths.apexDocs}`
2. **Compare each doc** against its current source code
3. **Flag stale docs**: docs that don't match the current source (missing methods, wrong descriptions, outdated field lists)
4. **Flag orphaned docs**: docs for components/classes that no longer exist
5. **Flag missing docs**: in-scope components/classes without doc files
6. **Report** a summary table: component name, status (current/stale/orphaned/missing)

## Documentation Format

Follow the existing format in `{paths.lwcDocs}` and `{paths.apexDocs}`. Reference:
- **SF-12: Apex Inline Documentation** (`docs/patterns/salesforce-patterns.md#apex-docs`) for Apex documentation standards
- **SF-13: LWC Inline Documentation** (`docs/patterns/salesforce-patterns.md#lwc-docs`) for LWC documentation standards

## Rules

- Follow the scoping rules strictly — do not document out-of-scope components
- Match the style of existing doc files in the same directory
- Always update the README index files when adding new entries
- When updating an existing doc, preserve any manually-added notes or context
- For `audit` mode, only report findings — do not modify any files
