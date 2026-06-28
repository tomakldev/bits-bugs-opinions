#!/usr/bin/env bash
set -euo pipefail

# PostToolUse hook: circuit breaker
# Tracks consecutive tool failures per session. After 3 consecutive failures
# of the same tool, injects a warning to force reassessment.
# Resets counter on any success.

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only track Bash and Agent tools (most prone to retry loops)
case "$TOOL_NAME" in
  Bash|Agent|mcp__*)
    ;;
  *)
    exit 0
    ;;
esac

# Get exit status / error indicator
IS_ERROR="false"
if [[ "$TOOL_NAME" == "Bash" ]]; then
  EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_output.exit_code // "0"')
  if [[ "$EXIT_CODE" != "0" ]]; then
    IS_ERROR="true"
  fi
else
  # For other tools, check if output contains error indicators
  OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // "" | tostring' 2>/dev/null || echo "")
  if echo "$OUTPUT" | grep -qiE '^(error|failed|exception|traceback)'; then
    IS_ERROR="true"
  fi
fi

# Session-scoped state file
STATE_DIR="/tmp/claude-1000/circuit-breaker"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/${TOOL_NAME//\//_}.count"

if [[ "$IS_ERROR" == "true" ]]; then
  # Increment failure counter
  CURRENT=0
  if [[ -f "$STATE_FILE" ]]; then
    CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  fi
  CURRENT=$((CURRENT + 1))
  echo "$CURRENT" > "$STATE_FILE"

  if [[ "$CURRENT" -ge 3 ]]; then
    # Reset counter so the warning fires once, not every subsequent call
    echo "0" > "$STATE_FILE"
    echo "CIRCUIT BREAKER: $TOOL_NAME has failed $CURRENT times consecutively. Stop retrying the same approach. Reassess: try a different command, check assumptions, or ask the user for guidance." >&2
  fi
else
  # Success resets the counter
  if [[ -f "$STATE_FILE" ]]; then
    echo "0" > "$STATE_FILE"
  fi
fi

exit 0
