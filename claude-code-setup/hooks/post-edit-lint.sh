#!/usr/bin/env bash
set -euo pipefail

# PostToolUse hook: lint TypeScript files after Write/Edit
# Only runs on .ts/.tsx files, warns on type errors without blocking

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

# Only check Write and Edit operations
if [[ "$TOOL_NAME" != "Write" && "$TOOL_NAME" != "Edit" ]]; then
  exit 0
fi

# Only check TypeScript files
if [[ ! "$FILE_PATH" =~ \.(ts|tsx)$ ]]; then
  exit 0
fi

# Skip node_modules and generated files
if [[ "$FILE_PATH" =~ node_modules/ || "$FILE_PATH" =~ \.d\.ts$ ]]; then
  exit 0
fi

# Check for debug statements in any source file (.ts, .tsx, .js, .jsx, .py, .sh)
if [[ "$FILE_PATH" =~ \.(ts|tsx|js|jsx)$ ]]; then
  DEBUG_HITS=$(grep -nE '^\s*(console\.(log|debug|warn|error|trace)|debugger\b)' "$FILE_PATH" 2>/dev/null | head -5) || true
  if [[ -n "$DEBUG_HITS" ]]; then
    echo "Debug statements found in $FILE_PATH:" >&2
    echo "$DEBUG_HITS" >&2
  fi
fi

# Run tsc --noEmit on the specific file (quick check)
# Use the project's tsconfig if available
PROJ_DIR=$(dirname "$FILE_PATH")
while [[ "$PROJ_DIR" != "/" ]]; do
  if [[ -f "$PROJ_DIR/tsconfig.json" ]]; then
    break
  fi
  PROJ_DIR=$(dirname "$PROJ_DIR")
done

ERRORS=""
if [[ -f "$PROJ_DIR/tsconfig.json" ]]; then
  ERRORS=$(cd "$PROJ_DIR" && npx tsc --noEmit --pretty false 2>&1 | grep -F "$FILE_PATH" | head -5) || true
else
  ERRORS=$(npx tsc --noEmit --pretty false "$FILE_PATH" 2>&1 | head -5) || true
fi

if [[ -n "$ERRORS" ]]; then
  # Log warning but don't block
  echo "TypeScript issues in $FILE_PATH:" >&2
  echo "$ERRORS" >&2
fi

exit 0
