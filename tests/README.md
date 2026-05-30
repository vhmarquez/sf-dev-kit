# Tests

A [bats](https://github.com/bats-core/bats-core) suite over argo's security-critical
hooks. It exercises the **enforcement contract** — what the guard and the
classification library allow vs. block — by faking the `sf` CLI boundary, so it
needs no Salesforce org, no network, and no credentials.

There is **no CI workflow by design** — run it locally (see the optional
pre-push hook below to gate your own pushes for free).

## Prerequisites

```bash
brew install bats-core      # macOS
# or: npm install -g bats    # or: sudo apt-get install bats
```

`jq` and a `sha256` tool (`shasum`/`sha256sum`) must also be present — they
already are if the plugin runs.

## Run

```bash
bash tests/run.sh           # checks for bats, then runs the suite
# or directly:
bats tests/                 # all files
bats tests/security_guard.bats   # one file
```

## What's covered

| File | Surface | Examples |
|------|---------|----------|
| `security_guard.bats` | `hooks/security-guard.sh` (PreToolUse, black-box: JSON in → exit code) | compound-command bypass, path-qualified/quoted `sf`, inline consent token, metadata-vs-data SOQL, no false positives on `git && sf deploy` |
| `classify.bats` | `hooks/lib/security.sh` (direct function calls → real `77`/`78` codes) | scratch→`dev`, sandbox, prod, `prodOrgAliases` hard-refuse, `knownNonSandboxNonProd`, no-cache-on-unknown, TTL re-derive, cache short-circuit, metadata-only-is-unconditional |
| `pmd.bats` | `hooks/lib/pmd.sh` | sha256 helper correctness, pinned-hash invariant |

## How the fakes work

- `tests/helpers/sf` is a configurable stand-in for the Salesforce CLI. Tests put
  `tests/helpers/` first on `PATH`, then declare org topology via env:
  `FAKE_SF_SCRATCH`, `FAKE_SF_SANDBOX`, `FAKE_SF_NONSCRATCH`, `FAKE_SF_FAIL`.
- `tests/helpers/common.bash` gives every test an isolated temp
  `CLAUDE_PROJECT_DIR` + `CLAUDE_PLUGIN_DATA`, plus helpers: `write_config`,
  `seed_cache`, `guard` (run the PreToolUse hook), `load_security_lib`.

These mirror the ad-hoc validation the hooks were developed against — the suite
just makes it permanent and re-runnable.

## Optional: gate your own pushes (free, local)

```bash
cat > .git/hooks/pre-push <<'EOF'
#!/bin/sh
exec bash "$(git rev-parse --show-toplevel)/tests/run.sh"
EOF
chmod +x .git/hooks/pre-push
```

Now `git push` runs the suite first and aborts on failure. (`.git/hooks` is local
and never committed, so this stays opt-in per clone.)

## Scope notes

- Tests fake `sf`/PMD network boundaries on purpose — they verify the **logic**
  (where the bugs were), not the real CLI/download.
- Run under `bash` (the hooks' `#!/bin/bash` shebang). On a stock macOS the system
  shell is zsh, where `declare -F` differs — bats invokes bash, matching production.
