#!/usr/bin/env bash
# Pre-deploy checks (run in parallel)

git status                         # working tree clean?
git log --oneline -5               # what's being deployed?
docker ps | grep trigger           # containers running?
# mcp__trigger__list_deploys       # current deployed version (MCP tool)
# mcp__trigger__list_runs          # recent run status (MCP tool)
