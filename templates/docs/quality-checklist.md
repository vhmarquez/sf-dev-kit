# Quality Checklist

Unified quality verification checklist for all Apex and LWC code. Used by agents (`@apex-dev`, `@lwc-dev`, `@qa`) and skills (`/code-review`). Specific values referenced below (API version, target org, coverage threshold) come from `.claude/sf-project.json`.

---

## Apex

### Security
- [ ] `with sharing` declared (or `without sharing` justified with `// reason: ...` comment)
- [ ] `inherited sharing` only used on utilities called from `with sharing` callers
- [ ] `WITH USER_MODE` or `WITH SECURITY_ENFORCED` on every SOQL touching sensitive objects
- [ ] `as user` (or `Database.X(records, AccessLevel.USER_MODE)`) on DML operations
- [ ] Input parameters validated before use (null → type → business rules → DML)
- [ ] Dynamic SOQL uses bind variables; dynamic fields whitelisted against `Set<String>` (SF-11) or escaped
- [ ] No SOQL injection vulnerabilities (run `/argo:security-scan`)
- [ ] No CRUD/FLS gaps (run `/argo:fls-audit`)
- [ ] All callouts use Named Credentials (SF-15) — no hardcoded endpoints/tokens
- [ ] No `without sharing` class reachable from an `@AuraEnabled` method without an explicit access check
- [ ] No PII (emails, phone, SSN, payment, auth) in `System.debug` or logger entries
- [ ] `@AuraEnabled` methods that take an `Id` verify the caller's access to that record (FLS + sharing)

### Governor Limits
- [ ] No SOQL inside loops
- [ ] No DML inside loops
- [ ] Queries use `LIMIT` where datasets could be large
- [ ] Bulk-safe: handles 200+ records in trigger context
- [ ] Async work uses static guard to prevent multiple enqueues

### Error Handling
- [ ] `@AuraEnabled` methods throw `AuraHandledException` with clean messages
- [ ] Specific exceptions caught before generic `Exception` (IllegalArgumentException → DmlException → Exception)
- [ ] No stack traces exposed to users
- [ ] Errors logged via `Logger` for debugging

### Code Quality
- [ ] Methods under 50 lines — extract private helpers
- [ ] No duplicated logic — extract to service/utility if reused
- [ ] Constants used for magic strings/numbers (`UPPER_SNAKE_CASE`)
- [ ] Naming follows conventions (PascalCase classes, camelCase methods, `{Feature}Controller`/`{Feature}Service`)

---

## LWC

### JavaScript
- [ ] `@track` only on objects/arrays, not primitives
- [ ] `@api` properties not mutated directly
- [ ] Getters used for computed values (not @track updated in callbacks)
- [ ] `lwc:if` used instead of `if:true` for conditional blocks
- [ ] `lwc:for` has `lwc:key` with stable unique ID (not array index)
- [ ] Events use `bubbles: true, composed: true` for cross-component communication
- [ ] User input debounced (300ms) before Apex calls
- [ ] Lifecycle: subscribe in `connectedCallback`, cleanup in `disconnectedCallback`
- [ ] No state changes in `renderedCallback` (infinite loop risk)
- [ ] `@wire` for read-only data, imperative for DML operations

### CSS
- [ ] SLDS utility classes used for spacing and layout before custom CSS
- [ ] No `!important` in CSS
- [ ] No direct SLDS class overrides (`.slds-button { ... }`)
- [ ] No hardcoded colors or pixel values — SLDS tokens or custom properties used
- [ ] Responsive grid classes for multi-column layouts (`slds-size_*`, `slds-medium-size_*`)
- [ ] Styling hooks (`:host { --slds-c-* }`) for base component customization

### HTML / Accessibility
- [ ] Labels on all form inputs (`label` prop on `lightning-*` components)
- [ ] `aria-label` on custom interactive elements
- [ ] Semantic HTML (buttons, not styled divs)
- [ ] Loading spinners have `alternative-text`
- [ ] Empty states handled (message when no records)
- [ ] Error states handled (user-friendly error messages)

### Meta XML
- [ ] `isExposed=true` for components that are placed by users (Experience Builder, App Builder)
- [ ] `<targets>` match `platform.lwcTargets` from `.claude/sf-project.json`
- [ ] API version matches `platform.apiVersion` from `.claude/sf-project.json`

---

## Agent (Agentforce / Headless 360)

### Trust Layer

- [ ] Einstein Trust Layer enabled at the org level (run `/argo:trust-layer-audit`)
- [ ] PII data masking active for the project's sensitive fields
- [ ] Zero-data-retention agreements signed with every configured LLM provider
- [ ] Grounding queries enforce FLS (`WITH USER_MODE` on every grounding SOQL)
- [ ] Toxicity / bias detection enabled

### Prompt safety

- [ ] System prompt delimits user input with explicit tags so injection cannot impersonate it
- [ ] No PII placeholders that the LLM would echo back; structured slots only
- [ ] No hardcoded org-specific URLs or 18-char Salesforce IDs in prompts (use Custom Metadata, SF-17)
- [ ] No "ignore previous instructions"-style phrasing in prompts (don't prime injection)

### Topics & guardrails

- [ ] Each topic owns one intent cluster; ≤2 bound actions per topic (decompose to sub-agents otherwise — AGT-1, AGT-2)
- [ ] Customer-facing agents have an `escalate_to_human` topic (AGT-7)
- [ ] Destructive actions use a `confirm-before-execute` topic flow (AGT-3)
- [ ] All MCP bridge specs in `mcp/bridges/` have `outputSchema` defined

### Eval suite

- [ ] At least 5 eval cases per agent under `tests/agent-evals/<agent>/`
- [ ] At least 1 prompt-injection / jailbreak case per customer-facing agent
- [ ] At least 1 escalation case
- [ ] At least 1 destructive-action case (must score 1.0 on action-correctness)
- [ ] `/argo:agent-test --ci --fail-on error` exits 0
- [ ] No regression vs. main per `/argo:agent-eval-trend pr`

### AI Gateway

- [ ] AI Gateway config exists for each environment (`.claude/ai-gateway[.<env>].json`)
- [ ] Per-agent token quotas set
- [ ] Fallback chain references only allowlisted models
- [ ] Audit log retention ≥ 30 days (dev) / 365 days (prod)
- [ ] Quota-exceeded webhook configured for prod
