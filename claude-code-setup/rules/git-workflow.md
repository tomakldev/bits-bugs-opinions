---
paths:
  - "**/*"
---
# Git Workflow Rules

- Always run `git status` before committing
- Use `gh` CLI for PRs and issues — never the web UI
- Commit messages: concise, focus on "why" not "what"
- Never force push to master
- Never commit `.env`, credentials, API keys, or tokens
- Check `.gitignore` before staging sensitive files
- Use specific file names in `git add` — avoid `git add -A` or `git add .`
- Problems repo: `your-org/devops-problems` — for tracking devops issues
- Main branch: `master`

## Agent-controlled git operations (CVE-2026-26268 hardening)

When an AI agent autonomously runs `git clone`, `git checkout`, or `git submodule` inside an untrusted repo, `.git/hooks/` scripts fire automatically with no warning.

For autonomous git operations in repos not fully controlled by this user:
- Use `git -c core.hooksPath=/dev/null <command>` to disable hooks
- Check `ls -la .git/hooks/` for executable files before checkout
- Never run `git submodule update` without first reviewing submodule URLs

Applies to: MCP git server operations, agent-issued checkout commands, cloning external repos during research or dependency checks.
