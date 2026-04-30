# Security Policy

## Reporting a vulnerability

If you find a security issue in `sf-dev-kit`, please report it confidentially via [**GitHub Private Vulnerability Reporting**](https://github.com/vhmarquez/sf-dev-kit/security/advisories/new). Don't file a public issue or describe the vulnerability in a public fork before it's been disclosed responsibly.

## What counts as a security vulnerability

Things that are security issues:

- The plugin makes an unintended call to a Salesforce org — especially one classified in `security.prodOrgAliases`
- A SOQL query against a customer-data target runs without firing a consent prompt
- The `PreToolUse` security guard (`hooks/security-guard.sh`) can be bypassed by a crafted Bash command
- The consent log skips entries that should be recorded
- A skill executes anonymous Apex (`sf apex run`) without a consent prompt, even when `security.allowAnonymousApex: false`
- Path traversal, command injection, or shell-injection in any hook script (`hooks/*.sh`, `hooks/lib/*.sh`)
- A way for a malicious project's `.claude/sf-project.json`, `.claude/sf-project.<env>.json`, or `.mcp.json` to escalate privileges or exfiltrate data
- A pattern pack's `pack.json` that can run arbitrary code during install

Things that are NOT security issues — please don't file these as advisories:

- A skill produces incorrect output (functional bug)
- A pattern recommendation you disagree with
- The plugin runs slowly
- Compatibility issues with a specific `sf` CLI or Node.js version

For non-security bugs, see the **Bug reports** section below.

## What to include in a report

- The version of `sf-dev-kit` (from `.claude-plugin/plugin.json`)
- The version of Claude Code, the `sf` CLI, and Node.js
- The OS / shell (Git Bash on Windows, macOS, Linux)
- Reproduction steps that surface the vulnerability
- The impact you observed (what data was exposed, what command ran, what should have been refused)
- Optionally, a suggested fix or mitigation

## Response

This is a solo project. I'll do my best to acknowledge reports within 7 days, but **no formal SLA is offered**. After acknowledgment I'll investigate, and if the issue is confirmed, coordinate disclosure and ship a fix as a point release.

## Disclosure timeline

I prefer **90-day responsible disclosure** — after a fix ships and a patched version is published, the report can be made public. Earlier public disclosure is welcome once a fix is in place. If a 90-day window doesn't fit your needs (e.g., you have a hard deadline from your own org's policy), say so in the report.

## Bug reports (non-security)

This plugin is developed solo, primarily for my own use. **I don't accept pull requests, feature requests, or bug-fix contributions.** The repo is MIT-licensed precisely so you can fork it and adapt it freely without going through me.

For non-security bugs, your options are:

1. **Fork and fix locally** — recommended; you control the timeline and the patch
2. **File the bug as a public issue** if GitHub Issues are enabled (they may not be — check the repo settings)

I may notice fork-and-fix patterns and reimplement the fix in this repo, but that's not a process you can rely on.
