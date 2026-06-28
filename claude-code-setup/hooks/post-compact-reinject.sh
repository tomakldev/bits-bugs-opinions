#!/usr/bin/env bash
set -euo pipefail

# PostCompact hook: re-inject critical context after context compaction
# Receives compact_summary in input; outputs reminder text for Claude

INPUT=$(cat)

SUMMARY=$(echo "$INPUT" | jq -r '.compact_summary // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Build re-injection prompt
cat <<REINJECT
POST-COMPACTION CONTEXT REFRESH:
- Working directory: ${CWD}
- Session: ${SESSION_ID}
- Re-read any active task list (TaskList) to recover in-progress work
- Check MEMORY.md and active plan files if the compacted summary references ongoing work
- If you were mid-edit on a file, re-read it to verify current state
- All rules from .claude/rules/ are still active (humanizer, security, untrusted-output)
REINJECT

exit 0
