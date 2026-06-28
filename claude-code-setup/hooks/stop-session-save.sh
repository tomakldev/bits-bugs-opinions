#!/usr/bin/env bash
set -euo pipefail

# Stop hook -- saves a minimal session record when conversation ends
# Logs timestamp + git changes to session log, sends Telegram if uncommitted work exists

INPUT=$(cat)

STOP_REASON=$(echo "$INPUT" | jq -r '.stop_reason // "unknown"')
SESSION_LOG="/home/tomakl/.claude/projects/-home-tomakl-projects/memory/sessions.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

# Gather git status
GIT_DIR="/home/tomakl/projects"
CHANGED_FILES=$(cd "$GIT_DIR" && git diff --name-only 2>/dev/null | head -20 || echo "")
UNTRACKED=$(cd "$GIT_DIR" && git ls-files --others --exclude-standard 2>/dev/null | head -10 || echo "")
BRANCH=$(cd "$GIT_DIR" && git branch --show-current 2>/dev/null || echo "unknown")

# Count changes
CHANGED_COUNT=0
if [[ -n "$CHANGED_FILES" ]]; then
  CHANGED_COUNT=$(echo "$CHANGED_FILES" | wc -l)
fi
UNTRACKED_COUNT=0
if [[ -n "$UNTRACKED" ]]; then
  UNTRACKED_COUNT=$(echo "$UNTRACKED" | wc -l)
fi

# Write session log entry
{
  echo "--- $TIMESTAMP | branch: $BRANCH | reason: $STOP_REASON | modified: $CHANGED_COUNT | untracked: $UNTRACKED_COUNT"
  if [[ -n "$CHANGED_FILES" ]]; then
    echo "  changed: $(echo "$CHANGED_FILES" | tr '\n' ', ' | sed 's/,$//')"
  fi
  if [[ -n "$UNTRACKED" ]]; then
    echo "  new: $(echo "$UNTRACKED" | tr '\n' ', ' | sed 's/,$//')"
  fi
} >> "$SESSION_LOG" 2>/dev/null || true

exit 0
