#!/usr/bin/env bash
set -euo pipefail

# PostToolUse hook: scan Bash output for leaked secrets/credentials
# Non-blocking (warns only), checks for common secret patterns in command output

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only check Bash tool output
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

OUTPUT=$(echo "$INPUT" | jq -r '.tool_output.stdout // empty')
STDERR=$(echo "$INPUT" | jq -r '.tool_output.stderr // empty')
COMBINED="${OUTPUT}${STDERR}"

# Skip if no output
if [[ -z "$COMBINED" ]]; then
  exit 0
fi

# Patterns that indicate leaked secrets (conservative to avoid false positives)
LEAKED=""

# API keys and tokens (long alphanumeric strings after key= or token= assignments)
if echo "$COMBINED" | grep -qEi '(api[_-]?key|secret[_-]?key|access[_-]?token|bearer)\s*[:=]\s*["\x27]?[A-Za-z0-9_\-]{20,}'; then
  LEAKED="${LEAKED}\n- Possible API key or token in output"
fi

# AWS keys
if echo "$COMBINED" | grep -qE 'AKIA[0-9A-Z]{16}'; then
  LEAKED="${LEAKED}\n- AWS access key ID detected"
fi

# Private keys
if echo "$COMBINED" | grep -q 'BEGIN.*PRIVATE KEY'; then
  LEAKED="${LEAKED}\n- Private key material detected"
fi

# Vault tokens
if echo "$COMBINED" | grep -qE 'hvs\.[A-Za-z0-9_\-]{20,}'; then
  LEAKED="${LEAKED}\n- Vault token detected"
fi

# Password in connection strings
if echo "$COMBINED" | grep -qEi '://[^:]+:[^@]{8,}@'; then
  LEAKED="${LEAKED}\n- Credentials in connection string"
fi

if [[ -n "$LEAKED" ]]; then
  echo "WARNING: Possible secret leak in command output:" >&2
  echo -e "$LEAKED" >&2
  echo "Review the output before sharing or committing." >&2
fi

exit 0
