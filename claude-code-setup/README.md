# Claude Code Setup

My production Claude Code configuration: 35+ custom agents, 20 hooks, rules, and skills.
This runs daily across DevOps, cloud infrastructure, incident analysis, and AI automation work.

Full write-up: [tomakl.dev](https://tomakl.dev)

---

## agents/

Specialized subagents with defined roles, tools, and reasoning strategies. Each agent is
scoped to a domain and called by the orchestrator or directly from skills.

| Agent | Purpose |
|---|---|
| `error-detective.md` | Root cause analysis across distributed systems |
| `vault-secret-rotator.md` | Audit and rotate HashiCorp Vault secrets |
| `code-reviewer.md` | Security, performance, and maintainability review |
| `team-lead.md` | Multi-agent orchestration coordinator |
| `devops-engineer.md` | CI/CD, deployment automation, infrastructure |
| `backend-architect.md` | API design, service boundaries, data modeling |
| `deploy-verifier.md` | Health checks and before/after deployment state |
| `prompt-engineer.md` | LLM prompt design, evals, and optimization |
| `search-specialist.md` | Deep web research with multi-source verification |
| `vault-secret-rotator.md` | Secret audit, age checks, and rotation |

---

## hooks/

Deterministic checks that run before and after every tool call. These are the gates
that stop agents from doing the wrong thing without asking first.

| Hook | Trigger | Purpose |
|---|---|---|
| `pre-tool-safety.sh` | PreToolUse | Block destructive ops on production without confirmation |
| `pre-tool-injection-scan.sh` | PreToolUse | Detect prompt injection in tool arguments |
| `post-tool-injection-scan.sh` | PostToolUse | Scan tool output for injection patterns |
| `post-bash-output-scan.sh` | PostToolUse | Flag sensitive data in bash output |
| `mcp-tofu-check.sh` | PreToolUse | Trust-on-first-use verification for MCP servers |
| `post-tool-circuit-breaker.sh` | PostToolUse | Rate limit and circuit-break runaway tool calls |
| `stop-session-save.sh` | Stop | Save session diary to pgvector RAG |
| `stop-goal-check.sh` | Stop | Verify session output matches the original goal |
| `post-compact-reinject.sh` | PostToolUse | Re-inject context after context compaction |
| `session-start-title.sh` | SessionStart | Set terminal title and load session context |
| `task-completed-notify.sh` | Notification | Push notification on task completion |
| `user-prompt-rating-capture.sh` | UserPromptSubmit | Capture prompt ratings for quality tracking |

---

## rules/

Always-loaded context that shapes agent behavior across every session.

| Rule | Purpose |
|---|---|
| `self-verification.md` | Chain-of-verification before destructive actions |
| `humanizer.md` | Remove AI writing patterns from all output |
| `rag-security.md` | Defend against RAG memory poisoning |
| `untrusted-output.md` | Prompt sandwiching for external tool output |
| `mcp-security.md` | MCP server trust and audit rules |
| `kg-agent-usage.md` | Knowledge graph conventions for agents |
| `rag-kb.md` | When and how to use the RAG knowledge base |

---

## skills/

Slash commands that orchestrate multi-step workflows.

| Skill | Purpose |
|---|---|
| `code-optimizer.md` | Analyze and refactor code for performance |
| `devops-diagnosis.md` | Structured incident diagnosis workflow |
| `text-humanizer.md` | Remove AI patterns from text |
| `pr-reviewer.md` | Full PR review with inline comments |
| `security-scan.md` | Security audit across OWASP top 10 |
