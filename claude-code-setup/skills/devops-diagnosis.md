---
name: devops-diagnosis
version: 1.0.0
description: |
  Multi-agent DevOps diagnosis pipeline. Use when the user reports application errors,
  log file issues, service failures, or needs root cause analysis for production systems.
  Triggers when error logs, stack traces, OutOfMemoryError, connection timeouts, or
  service-down scenarios are mentioned. Also trigger when the user pastes Java exceptions,
  Python tracebacks, or says things like "the app is down", "getting 500 errors",
  "something broke in production", or shares a log file path. Coordinates specialized
  agents for investigation, analysis, documentation, and ticketing.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, Task, WebFetch, WebSearch, AskUserQuestion
---

# DevOps diagnosis pipeline

Multi-agent root cause analysis. Strategy: cot (step-by-step across agents).

## Agent roles

| Agent | MCP/Tools | Role |
|-------|-----------|------|
| confluence-searcher | Atlassian MCP | Find existing solutions |
| web-researcher | Tavily MCP | Web research for bugs, CVEs |
| docs-researcher | Context7 MCP | Library documentation |
| codebase-investigator | bash (rg) | Source code search |
| enterprise-app-specialist | All tools | Root cause analysis + fix |
| confluence-writer | Atlassian MCP | Generate + publish runbook |
| ticket-writer | Text generation | Ticket summary |
| github-ops | bash (gh CLI) | Issue creation |

## Input

Extract from user message:
- App name: lapa, sjk, netposti, kontakti (auto-detect from log path if not given)
- Log file path or error text

## Pipeline

1. **Resolve app** -- load app profile, extract error keywords from logs
2. **Confluence search** -- delegate to confluence-searcher for existing solutions
3. **Extended knowledge** -- launch 3 agents in parallel: web-researcher, docs-researcher, codebase-investigator
4. **Root cause analysis** -- delegate all findings to enterprise-app-specialist (opus)
5. **Documentation** -- ask user: Confluence / Local MD / Skip
6. **Ticket** -- delegate to ticket-writer for Jira/ServiceNow format

## Decision points

- After step 2: if SOLUTION_FOUND, ask user to continue or skip to docs
- After step 4: if SCRIPT_NEEDED, create GitHub issue via github-ops
- Step 5 is always interactive (user chooses documentation target)
