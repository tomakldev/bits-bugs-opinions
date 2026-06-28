#!/usr/bin/env bash
set -euo pipefail

# Stop hook: goal-directed loop continuation
# If ~/.claude/goal.txt exists, check if the goal is met.
# If not met, return additionalContext to keep Claude working autonomously.
# Create ~/.claude/goal.txt with the goal condition, delete it when done.

GOAL_FILE="${HOME}/.claude/goal.txt"

if [[ ! -f "$GOAL_FILE" ]]; then
  exit 0
fi

GOAL=$(cat "$GOAL_FILE")

if [[ -z "$GOAL" ]]; then
  rm -f "$GOAL_FILE"
  exit 0
fi

# Return additionalContext so Claude continues working toward the goal
printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"Goal not yet marked complete: %s\n\nContinue working toward this goal. When achieved, delete ~/.claude/goal.txt to stop the loop."}}\n' \
  "$(echo "$GOAL" | head -1)"
