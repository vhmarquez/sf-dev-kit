### Agentforce
- [ ] Each topic owns one intent cluster; ≤2 bound actions per topic (decompose to sub-agents otherwise — AGT-1, AGT-2)
- [ ] System prompt delimits user input with explicit `<user_input>` tags (AGT-3)
- [ ] All actions reference an MCP tool defined in `mcp/bridges/` (AGT-4); inline Apex actions justified with `// reason: ...` comments
- [ ] Every grounding SOQL uses `WITH USER_MODE` (AGT-5)
- [ ] Memory is in Curated Memory or `Agent_Conversation__c` — never in the prompt window (AGT-6)
- [ ] Customer-facing agents have an `escalate_to_human` topic (AGT-7)
- [ ] Eval suite has ≥5 cases including 1 jailbreak/prompt-injection, 1 escalation, 1 destructive-action
- [ ] Sub-agents have their own eval suite at `tests/agent-evals/<sub-agent-name>/`
