#!/bin/bash
# session-start.sh — One-line first-run nudge when a fresh SFDX project is detected.
#
# Triggered by the SessionStart hook in hooks.json. Output (stdout) is added to
# the session's initial context so the assistant can surface it to the user
# naturally on the first turn. Silent in all other cases — never adds noise to
# sessions that don't need it.
#
# Conditions for emitting the nudge (all must be true):
#   1. CLAUDE_PROJECT_DIR is set (we have a project context)
#   2. <project>/sfdx-project.json exists (this is a Salesforce DX project)
#   3. <project>/.claude/sf-project.json does NOT exist (no bootstrap yet)
#
# If any condition is false, exit 0 silently.
#
# Disable per-session for testing: SF_DEV_KIT_SESSION_NUDGE=0

set -u

if [[ "${SF_DEV_KIT_SESSION_NUDGE:-1}" == "0" ]]; then
  exit 0
fi

[[ -z "${CLAUDE_PROJECT_DIR:-}" ]] && exit 0
[[ -f "${CLAUDE_PROJECT_DIR}/sfdx-project.json" ]] || exit 0
[[ -f "${CLAUDE_PROJECT_DIR}/.claude/sf-project.json" ]] && exit 0

# Detect React/agent surfaces so the nudge can mention what /sf-init will set up.
extras=""
if [[ -d "${CLAUDE_PROJECT_DIR}/force-app/main/default/react" ]] 2>/dev/null; then
  extras+=" React component sources detected — /sf-init will scope React standards in."
fi
if find "${CLAUDE_PROJECT_DIR}/force-app" -maxdepth 6 -name '*.botDefinition-meta.xml' 2>/dev/null | head -1 | grep -q . ; then
  extras+=" Agentforce agents detected — /sf-init will scope agent paths in."
fi

cat <<EOF
[sf-dev-kit] This looks like a Salesforce DX project (sfdx-project.json found)
            but \`.claude/sf-project.json\` doesn't exist yet.

            Run \`/sf-dev-kit:sf-init\` to bootstrap. Detection is aggressive —
            most fields auto-fill from sfdx-project.json, package.json, and
            \`sf org list\`. You'll typically only confirm the target org and
            answer one "what is this project for?" question.

            The first run also classifies every non-sandbox org alias as
            production (hard-blocked) or known-non-prod (allowed). Production
            orgs are refused unconditionally once classified —
            see docs/security-model.md.${extras}
EOF

exit 0
