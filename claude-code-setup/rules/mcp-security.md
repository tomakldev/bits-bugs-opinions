---
paths:
  - "**/*"
---
# MCP Server Security

## Before installing any new MCP server

1. Run `uvx snyk-agent-scan scan ~/.claude/settings.json` (needs `SNYK_TOKEN` from Vault `secret/snyk`). Inspect-only: `uvx mcp-scan@0.4.3 inspect <config>`.
2. Review exposed tools — every tool is callable by the LLM.
3. Audit for unvalidated `path`/`url` params in tool definitions.
4. Never install from unverified npm packages.

## Tool poisoning / rug pull

Tool descriptions can change silently after initial approval. Pin server versions, never allow auto-updates. Re-run `mcp-scan` after any server update.

## MCP sampling: default deny

`sampling/createMessage` lets servers inject prompts. Never auto-approve. Show every sampling prompt before execution.

## Audit

Run `uvx mcp-scan scan` periodically; flag any new servers vs last baseline.

## Sensitivity tiers

- **Tier 1 (sensitive)**: vault-related, filesystem with write access, git operations, cloud providers (AWS/Azure) — require explicit per-capability approval, no auto-trust
- **Tier 2 (moderate)**: Atlassian, Telegram, Playwright, RAG — trust but log all tool invocations
- **Tier 3 (read-only)**: search, docs, context7 — standard operation

## Rule of Two: compound injection risk

Agent workflows must not simultaneously hold all three of:
1. Untrusted input (RAG search, web fetch, user uploads, Playwright)
2. Secrets access (Vault, env vars, API keys, az CLI with credentials)
3. External write (Telegram reply, email send, git push, Confluence write)

Any two is acceptable. All three in a single agent scope is exploitable -- a prompt injection in RAG or a web result can chain through secrets to exfiltrate via the write path (demonstrated in CVE-2026-GitHub-Actions-Claude-Code).

For lapa-incident and similar workflows: use a dedicated read-only agent for untrusted input gathering, a separate agent (seeded only from KG and known-good config) for az CLI / secrets operations.

## Remote MCP server authentication

Remote MCP servers must use OAuth 2.1 + PKCE S256 (RFC 9728 + RFC 8707). API key auth is acceptable only for localhost or private-network servers. No token passthrough between agents (MCP RC 2026 mandate).

## MCP stateless protocol migration (deadline: 2026-07-28)

MCP RC 2026-07-28 removes stateful sessions: `Mcp-Session-Id` header and `initialize` handshake are gone. Self-hosted MCP servers that rely on session state must be updated before July 28, 2026. Affected servers in this setup: rag-server, any custom stdio servers.
