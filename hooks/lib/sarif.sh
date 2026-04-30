#!/bin/bash
# sarif.sh — Convert argo internal findings JSON to SARIF 2.1.0.
#
# Internal finding shape (input on stdin, JSON array):
#   [
#     {
#       "ruleId":   "SF-5",                    (required)
#       "severity": "error|warning|note",      (default: warning)
#       "message":  "Human-readable text",     (required)
#       "file":     "force-app/.../X.cls",     (required, project-relative)
#       "line":     42,                        (default: 1)
#       "column":   1,                         (default: 1)
#       "endLine":  46,                        (optional)
#       "ruleHelpUri": "https://...",          (optional, per finding)
#       "tool":     "code-review|security-scan|dead-code|..."  (optional, sub-tool tag)
#     }
#   ]
#
# Public function:
#   sarif_emit  [tool-name] [tool-version]  — read findings JSON from stdin, write SARIF to stdout

sarif_emit() {
  local tool_name="${1:-argo}"
  local tool_version="${2:-1.1.0}"

  if ! command -v jq >/dev/null 2>&1; then
    echo "[argo] Error: jq required for SARIF output" >&2
    return 1
  fi

  jq --arg name "$tool_name" --arg version "$tool_version" '
    def level(s): if s == "error" then "error"
                  elif s == "note"  then "note"
                  else "warning" end;

    {
      "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
      version: "2.1.0",
      runs: [{
        tool: {
          driver: {
            name: $name,
            version: $version,
            informationUri: "https://github.com/vmarquez/argo",
            rules: (
              [.[] | { id: .ruleId, helpUri: (.ruleHelpUri // null) }]
              | unique_by(.id)
              | map(. | with_entries(select(.value != null)))
            )
          }
        },
        results: map({
          ruleId: .ruleId,
          level: level(.severity // "warning"),
          message: { text: .message },
          locations: [{
            physicalLocation: {
              artifactLocation: { uri: .file },
              region: (
                { startLine: (.line // 1), startColumn: (.column // 1) }
                + (if .endLine then { endLine: .endLine } else {} end)
              )
            }
          }]
        } + (if .tool then { properties: { tool: .tool } } else {} end))
      }]
    }
  '
}
