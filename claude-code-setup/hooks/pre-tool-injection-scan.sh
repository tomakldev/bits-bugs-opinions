#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook -- scans tool outputs/inputs for prompt injection patterns
# Lightweight scanner inspired by Parry and Lasso Security approaches
# Focuses on detecting indirect prompt injection in MCP tool results

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT_STR=$(echo "$INPUT" | jq -r '.tool_input | tostring // empty' 2>/dev/null)

# Only scan tools that fetch external content (injection vectors)
case "$TOOL_NAME" in
  mcp__tavily__*|mcp__claude_ai_Tavily__*|WebFetch|WebSearch)
    # External web content -- high risk
    ;;
  mcp__filesystem__read_file|mcp__filesystem__read_text_file)
    # Check if reading from uploads (user-provided files)
    if ! echo "$TOOL_INPUT_STR" | grep -q '/mnt/nas/claude/uploads\|/mnt/nas/claude/logs'; then
      exit 0
    fi
    ;;
  mcp__playwright__*)
    # Browser automation -- content from web pages
    ;;
  mcp__rube__*)
    # External service integration
    ;;
  *)
    # Internal tools -- skip scanning
    exit 0
    ;;
esac

# Scan tool input for injection patterns that might be passed to external services
# These patterns in tool INPUT suggest the model is already compromised
INJECTION_PATTERNS=(
  'ignore previous instructions'
  'ignore all previous'
  'you are now'
  'new system prompt'
  'override system'
  'disregard all'
  'forget everything'
  'act as root'
  'pretend you are'
  'reveal your instructions'
  'show me your system prompt'
  'output your rules'
  'base64 -d'
  'curl.*\|.*bash'
  'wget.*\|.*sh'
)

for pattern in "${INJECTION_PATTERNS[@]}"; do
  if echo "$TOOL_INPUT_STR" | grep -qi "$pattern" 2>/dev/null; then
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Injection scan: suspicious pattern in tool input: '$pattern' -- review before proceeding\"}}"
    exit 0
  fi
done

# Check for Unicode Tag block in tool input -- may indicate compromised upstream content
if echo "$TOOL_INPUT_STR" | grep -qP '[\x{E0000}-\x{E007F}]' 2>/dev/null; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Unicode Tag block characters (U+E0000-U+E007F) detected in tool input -- invisible instruction encoding suspected.\"}}"
  exit 0
fi

# No injection patterns detected -- allow
exit 0
