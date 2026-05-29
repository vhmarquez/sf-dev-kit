# Security Model

The plugin operates under four hard invariants. They're enforced centrally — every org-touching skill routes through the same library — with a best-effort, defense-in-depth Bash hook (see [Known limitations](#known-limitations)) that gates raw `sf` calls which bypass the library.

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
${CLAUDE_PLUGIN_DATA}/argo/org-cache/<alias>.json
                                → cached org classification (sandbox/prod/unknown)
${CLAUDE_PLUGIN_DATA}/argo/consent-log/<project>.jsonl
                                → log of consent grants (allow-once decisions)
```

## Config

`.claude/sf-project.json`:

```json
{
  "security": {
    "prodOrgAliases":         ["ProdProd"],
    "knownNonSandboxNonProd": [],
    "allowAnonymousApex":     false
  }
}
```

| Field | Purpose |
|-------|---------|
| `prodOrgAliases` | Aliases the plugin must never contact. Hard-refuse, no override. |
| `knownNonSandboxNonProd` | Non-sandbox orgs (developer / demo orgs) explicitly classified as OK to contact. Without this, any non-sandbox alias not in `prodOrgAliases` is treated as unclassified and refused. |
| `allowAnonymousApex` | When `false` (default), `sf apex run` is refused outright. When `true`, it's available behind a per-call consent prompt. |

The metadata-only SOQL allowlist is **always enforced** — there is no toggle to disable it. Any query against a non-allowlisted (customer-data) object requires explicit per-call consent (invariant #2), on every org, with no opt-out.

## Wire protocol

When a security check fires, it emits a JSON event on stderr and exits with one of:

| Exit code | Meaning |
|-----------|---------|
| `0` | Allowed |
| `77` | Consent required — overridable. The assistant should present the event to the user and, on grant, re-invoke with `ARGO_CONSENT_GRANTED=once` |
| `78` | Hard refusal — not overridable in this session |
| `2` | Invocation error (bad arguments, missing dependencies) |

These codes are the **library's** internal protocol (`sf-cli.sh` / `mcp.sh` routes). The `PreToolUse` Bash guard (`security-guard.sh`) follows the hook contract instead: it collapses both `77` and `78` to **exit `2`** (which blocks the tool call) while preserving the same JSON event on stderr, so the assistant still distinguishes `event: consent_required` from `refused`.

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
[argo/security] CONSENT REQUIRED

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

Granting `[a]` re-invokes the gated command after `export ARGO_CONSENT_GRANTED=once` (the PreToolUse guard also accepts the token inline, as `ARGO_CONSENT_GRANTED=once sf …`). The token is consumed immediately, so a second restricted call inside the same skill run prompts again.

## Consent log

Every consent grant appends one JSON line to `${CLAUDE_PLUGIN_DATA}/argo/consent-log/<project>.jsonl`:

```json
{"ts":"2026-04-30T19:45:23Z","skill":"trust-eval","action":"soql","scope":"AgentSessionTrace@DevVM","decision":"allow-once"}
{"ts":"2026-04-30T19:45:24Z","skill":"trust-eval","action":"soql","scope":"AgentSessionTrace@DevVM","decision":"allow-once"}
{"ts":"2026-04-30T19:45:25Z","skill":"trust-eval","action":"soql","scope":"AgentSessionTrace@DevVM","decision":"allow-once"}
```

This records consent **grants** (`allow-once`, and `metadata-only-disabled` reads) — not refusals or prod-block events. Review what's been granted, when, and against which org.

## Org classification

For each non-sandbox alias `sf org list` knows about, classification is cached at `${CLAUDE_PLUGIN_DATA}/argo/org-cache/<alias>.json`:

```json
{ "alias": "DevVM", "classification": "sandbox", "username": "dev@vm.example", "classifiedAt": "2026-04-30T19:45:00Z", "classifiedAtEpoch": 1780000000 }
```

Possible classifications:
- `sandbox` — `sf org display --json` reported `isSandbox: true`. Allowed.
- `prod` — reported `isSandbox: false`. **Hard-refused unless explicitly classified** in `security.prodOrgAliases` (still refused, by design) or `security.knownNonSandboxNonProd` (allowed).
- `unknown` — classification call failed. Refused with a `consent_required` event asking the user to classify manually. **Never cached**, so a transient failure self-heals on the next call.

The cache is a **performance hint, not a trust anchor**: `security.prodOrgAliases` is consulted *before* the cache on every call, so a stale or hand-edited cache cannot promote a listed prod org to `sandbox`. Cached verdicts expire after `ARGO_ORG_CACHE_TTL` seconds (default 7 days) and are re-derived — so an alias re-authed to a different org can't ride a stale verdict indefinitely. The `username` stamp records which org backed the alias when it was classified. Cache and consent-log files are written `0600`. Re-classify immediately by deleting the cache file and re-running the targeting skill.

## Per-skill data access (frontmatter)

Every skill's frontmatter declares its data-access surface:

| Value | Meaning | Skills |
|-------|---------|--------|
| `none` | No org contact at all | 30 (decision helpers, doc generators, source analyzers, packs, notifications) |
| `metadata-only` | May contact orgs but only for metadata-shaped operations (deploys, retrieves, schema describes, allowlisted SOQL) | 23 (deploys, org-explore, agent-discover, mcp-* skills, etc.) |
| `data-with-consent` | Fundamentally needs to read customer data; prompts every run | 3 (`trust-eval`, `permset-audit`, `agent-test`) |

Run `grep -l 'data-access: data-with-consent' skills/*/SKILL.md` to enumerate.

## Belt-and-suspenders: PreToolUse Bash hook

`hooks/security-guard.sh` runs before every `Bash` tool call. It **splits the command on shell separators** (`;`, `&&`, `||`, `|`, `&`, newline) and gates **every** `sf` invocation it finds independently — parsing subcommand + target alias + SOQL for each. This catches:
- Skills that bypass `sf-cli.sh` and call `sf` directly
- Hand-written Bash from the assistant that targets prod or queries data
- Compound commands (`sf org list; sf data query … -o prod`) — each segment is gated, so prefixing a benign `sf` verb does not slip a later segment past the guard
- `sf` invoked by absolute path (`/usr/local/bin/sf …`) or quoted (`'sf' …`) — detection is basename-aware

It also honors the documented re-invoke form: an inline `ARGO_CONSENT_GRANTED=once sf …` is lifted out of the command and applied for that single call.

The hook is registered in `hooks/hooks.json` under `PreToolUse` matcher `Bash`. Disable per-session for testing with `ARGO_SECURITY_GUARD=0` (NOT recommended — disables the safety net while leaving the library checks intact).

### Known limitations

The Bash guard is a best-effort, regex-based safety net — **the library (`security.sh`) is the authoritative enforcement layer.** The guard intentionally cannot catch:
- `sf` reached through **shell indirection** — variable expansion (`S=sf; $S data query …`), `eval`, command substitution, or shell aliases. A static guard cannot resolve these; such commands don't route through the library either, so don't hand-roll them against data/prod.
- When `jq` is **absent**, the guard cannot parse the tool input; it **fails closed** for recognizably-dangerous patterns (`sf data …`, `sf apex run`, `sf agent run/test`) and fails open otherwise. Install `jq` for full coverage.
- Operations issued without `--target-org` are gated against the configured `defaultTargetOrg`, which may differ from the CLI's own default target.

## Recommended posture

For a typical dev project:
1. Run `/argo:sf-init` — it detects every non-sandbox alias `sf org list` knows about and prompts you to classify each one as prod or known-non-prod.
2. Keep `security.allowAnonymousApex: false` (the default). The metadata-only SOQL allowlist is always enforced.
3. Allow consent prompts to fire on a per-call basis. Every grant lands in the consent log; review periodically.

For CI: run with `ARGO_SECURITY=1` (default), the guard hook enabled (default), and never `ARGO_CONSENT_GRANTED=once` in the env. CI cannot grant consent.

## Threat model

What this protects against:
- **Accidental writes / queries against prod** — alias-list block + classification cache
- **Skill-prompt injection that asks Claude to "just run a query against the customer table"** — security library refuses non-allowlisted SOQL targets
- **A future skill update that adds an unintended data query** — guard hook catches it at the Bash layer
- **Privilege escalation via anonymous Apex** — refused outright by default

What this does NOT protect against:
- Compromise of the user's local `sf` CLI auth state — out of scope
- The user explicitly setting `prodOrgAliases: []` and consenting to every prompt
- `sf` invoked through shell indirection (`$VAR`, `eval`, aliases) in hand-written Bash — the regex guard cannot resolve these; the library remains the enforcement layer for any call that routes through it (see [Known limitations](#known-limitations))
- Vulnerabilities in `@salesforce/mcp` itself
- Information that flows to the Anthropic API as part of the normal Claude Code session — that's the standard data flow; this plugin doesn't add to it
