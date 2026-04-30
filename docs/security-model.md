# Security Model

The plugin operates under four hard invariants. They're enforced centrally — every org-touching skill routes through the same library — with a defense-in-depth Bash hook that catches anything that might bypass the library.

## Invariants

1. **No contact with orgs classified as production.** Aliases listed in `security.prodOrgAliases` are refused unconditionally. No reads, no metadata fetches, no `sf org display`. Production agent quality, deploys, and inspection happen via Salesforce's own tooling, not this plugin.
2. **Metadata-only across all orgs by default.** SOQL targets must be on the metadata allowlist (`ApexClass`, `EntityDefinition`, `Profile`, `Flow`, `AgentDefinition`, etc., plus any `*__mdt`). Customer-data objects (`Account`, custom `__c`, `AgentSessionTrace`, `User`, `ContentDocument`, etc.) require explicit per-call user consent.
3. **Anonymous Apex disabled by default.** `sf apex run` (which can do anything in the org) is refused outright. When `security.allowAnonymousApex: true` is set, every individual call still prompts for consent.
4. **Overrides are runtime-only.** There are no persistent "always allow" grants. Every restricted call prompts the user. By design.

## Where the rules live

```
hooks/lib/security.sh           → primary enforcement library
hooks/security-guard.sh         → PreToolUse hook on Bash; defense-in-depth
hooks/lib/sf-cli.sh             → wraps `sf` calls; routes through security.sh
hooks/lib/mcp.sh                → wraps MCP calls; routes through security.sh
.claude/sf-project.json         → user's `security` config section
${CLAUDE_PLUGIN_DATA}/sf-dev-kit/org-cache/<alias>.json
                                → cached org classification (sandbox/prod/unknown)
${CLAUDE_PLUGIN_DATA}/sf-dev-kit/consent-log/<project>.jsonl
                                → audit log of every override granted
```

## Config

`.claude/sf-project.json`:

```json
{
  "security": {
    "prodOrgAliases":         ["ProdProd"],
    "knownNonSandboxNonProd": [],
    "metadataOnly":           true,
    "allowAnonymousApex":     false
  }
}
```

| Field | Purpose |
|-------|---------|
| `prodOrgAliases` | Aliases the plugin must never contact. Hard-refuse, no override. |
| `knownNonSandboxNonProd` | Non-sandbox orgs (developer / demo orgs) explicitly classified as OK to contact. Without this, any non-sandbox alias not in `prodOrgAliases` is treated as unclassified and refused. |
| `metadataOnly` | When `true` (default), SOQL queries must target the metadata allowlist. Setting to `false` disables the allowlist (still a per-call prompt for data targets unless consent granted) — not recommended; loosen only if you're working in a fully-isolated dev org. |
| `allowAnonymousApex` | When `false` (default), `sf apex run` is refused outright. When `true`, it's available behind a per-call consent prompt. |

## Wire protocol

When a security check fires, it emits a JSON event on stderr and exits with one of:

| Exit code | Meaning |
|-----------|---------|
| `0` | Allowed |
| `77` | Consent required — overridable. The assistant should present the event to the user and, on grant, re-invoke with `SF_DEV_KIT_CONSENT_GRANTED=once` |
| `78` | Hard refusal — not overridable in this session |
| `2` | Invocation error (bad arguments, missing dependencies) |

Event shape:

```json
{
  "event":   "consent_required" | "refused",
  "reason":  "PROD_ORG_BLOCKED" | "SOQL_DATA_OBJECT" | "ANON_APEX_DISABLED" | ...,
  "skill":   "<skill name>",
  "action":  "soql" | "metadata-read" | "metadata-write" | "anon-apex" | "data-write",
  "target":  "<sObject API name | command tail | empty>",
  "org":     "<alias>",
  "message": "<one-line human description>"
}
```

## Consent UX

When a skill needs to query a data object (or run anon Apex), the assistant presents:

```
[sf-dev-kit/security] CONSENT REQUIRED

Skill:    /<skill>
Org:      <alias>
Action:   <soql query / anon apex / data write>
Records:  <scope estimate>
What enters your conversation context with Claude:
  • <specific data exposed>
  • <…>

Choose:
  [a] Allow once       — runs this call; logs to consent log
  [d] Deny this part   — skip this portion, continue with the rest of the skill
  [c] Cancel           — abort the skill
```

Granting `[a]` re-invokes the gated command after `export SF_DEV_KIT_CONSENT_GRANTED=once`. The library consumes the token immediately, so a second restricted call inside the same skill run prompts again.

## Consent log

Every consent grant appends one JSON line to `${CLAUDE_PLUGIN_DATA}/sf-dev-kit/consent-log/<project>.jsonl`:

```json
{"ts":"2026-04-30T19:45:23Z","skill":"trust-eval","action":"soql","scope":"AgentSessionTrace@DevVM","decision":"allow-once"}
{"ts":"2026-04-30T19:45:24Z","skill":"trust-eval","action":"soql","scope":"AgentSessionTrace@DevVM","decision":"allow-once"}
{"ts":"2026-04-30T19:45:25Z","skill":"trust-eval","action":"soql","scope":"AgentSessionTrace@DevVM","decision":"allow-once"}
```

Audit-friendly. You can review what's been granted, when, and against which org.

## Org classification

For each non-sandbox alias `sf org list` knows about, classification is cached at `${CLAUDE_PLUGIN_DATA}/sf-dev-kit/org-cache/<alias>.json`:

```json
{ "alias": "DevVM", "classification": "sandbox", "classifiedAt": "2026-04-30T19:45:00Z" }
```

Possible classifications:
- `sandbox` — `sf org display --json` reported `isSandbox: true`. Allowed.
- `prod` — reported `isSandbox: false`. **Hard-refused unless explicitly classified** in `security.prodOrgAliases` (still refused, by design) or `security.knownNonSandboxNonProd` (allowed).
- `unknown` — classification call failed. Refused with a "consent_required" event asking the user to classify manually.

Re-classify by deleting the cache file and re-running the targeting skill.

## Per-skill data access (frontmatter)

Every skill's frontmatter declares its data-access surface:

| Value | Meaning | Skills |
|-------|---------|--------|
| `none` | No org contact at all | 30 (decision helpers, doc generators, source analyzers, packs, notifications) |
| `metadata-only` | May contact orgs but only for metadata-shaped operations (deploys, retrieves, schema describes, allowlisted SOQL) | 23 (deploys, org-explore, agent-discover, mcp-* skills, etc.) |
| `data-with-consent` | Fundamentally needs to read customer data; prompts every run | 3 (`trust-eval`, `permset-audit`, `agent-test`) |

Run `grep -l 'data-access: data-with-consent' skills/*/SKILL.md` to enumerate.

## Belt-and-suspenders: PreToolUse Bash hook

`hooks/security-guard.sh` runs before every `Bash` tool call. It scans the command for `sf` invocations, parses subcommand + target alias + SOQL, and gates accordingly. This catches:
- Skills that bypass `sf-cli.sh` and call `sf` directly
- Hand-written Bash from the assistant that targets prod or queries data
- Compound commands (`cmd1 && sf data query …`)

The hook is registered in `hooks/hooks.json` under `PreToolUse` matcher `Bash`. Disable per-session for testing with `SF_DEV_KIT_SECURITY_GUARD=0` (NOT recommended — disables the safety net while leaving the library checks intact).

## Recommended posture

For a typical dev project:
1. Run `/sf-dev-kit:sf-init` — it detects every non-sandbox alias `sf org list` knows about and prompts you to classify each one as prod or known-non-prod.
2. Keep `security.metadataOnly: true` and `security.allowAnonymousApex: false` (the defaults).
3. Allow consent prompts to fire on a per-call basis. Every grant lands in the consent log; review periodically.

For CI: run with `SF_DEV_KIT_SECURITY=1` (default), the guard hook enabled (default), `security.metadataOnly: true`, and never `SF_DEV_KIT_CONSENT_GRANTED=once` in the env. CI cannot grant consent.

## Threat model

What this protects against:
- **Accidental writes / queries against prod** — alias-list block + classification cache
- **Skill-prompt injection that asks Claude to "just run a query against the customer table"** — security library refuses non-allowlisted SOQL targets
- **A future skill update that adds an unintended data query** — guard hook catches it at the Bash layer
- **Privilege escalation via anonymous Apex** — refused outright by default

What this does NOT protect against:
- Compromise of the user's local `sf` CLI auth state — out of scope
- The user explicitly setting `prodOrgAliases: []` and consenting to every prompt
- Vulnerabilities in `@salesforce/mcp` itself
- Information that flows to the Anthropic API as part of the normal Claude Code session — that's the standard data flow; this plugin doesn't add to it. See README "How orgs are discovered" for the breakdown.
