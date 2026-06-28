#!/usr/bin/env bash
set -euo pipefail

# Git pre-commit hook: validate staged files before commit
# Catches debug statements, hardcoded secrets, and TypeScript errors
# Install: git config core.hooksPath .claude/hooks/git-hooks

STAGED=$(git diff --cached --name-only --diff-filter=ACM)

if [[ -z "$STAGED" ]]; then
  exit 0
fi

ERRORS=0
WARNINGS=0

# Check each staged file
while IFS= read -r FILE; do
  # Skip non-existent files (deleted) and hook scripts (contain detection patterns)
  [[ -f "$FILE" ]] || continue
  [[ "$FILE" =~ \.claude/hooks/ ]] && continue

  # Secret patterns (critical - blocks commit)
  if grep -nEi '(api[_-]?key|secret[_-]?key|password|token)\s*[:=]\s*["\x27][A-Za-z0-9_\-]{16,}' "$FILE" 2>/dev/null | grep -v '\.example\|\.template\|EXAMPLE\|PLACEHOLDER\|your-.*-here' > /dev/null; then
    echo "CRITICAL: Possible hardcoded secret in $FILE" >&2
    grep -nEi '(api[_-]?key|secret[_-]?key|password|token)\s*[:=]\s*["\x27][A-Za-z0-9_\-]{16,}' "$FILE" | head -3 >&2
    ERRORS=$((ERRORS + 1))
  fi

  # AWS keys (critical)
  if grep -nE 'AKIA[0-9A-Z]{16}' "$FILE" 2>/dev/null > /dev/null; then
    echo "CRITICAL: AWS access key in $FILE" >&2
    ERRORS=$((ERRORS + 1))
  fi

  # Private keys (critical)
  if grep -n 'BEGIN.*PRIVATE KEY' "$FILE" 2>/dev/null > /dev/null; then
    echo "CRITICAL: Private key material in $FILE" >&2
    ERRORS=$((ERRORS + 1))
  fi

  # Debug statements in JS/TS (warning)
  if [[ "$FILE" =~ \.(ts|tsx|js|jsx)$ ]]; then
    DEBUG=$(grep -nE '^\s*(console\.(log|debug)|debugger\b)' "$FILE" 2>/dev/null | head -5) || true
    if [[ -n "$DEBUG" ]]; then
      echo "WARNING: Debug statements in $FILE:" >&2
      echo "$DEBUG" >&2
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # .env files should never be committed
  if [[ "$FILE" =~ \.env($|\.) ]] && [[ ! "$FILE" =~ \.example$ ]] && [[ ! "$FILE" =~ \.template$ ]]; then
    echo "CRITICAL: Attempting to commit env file: $FILE" >&2
    ERRORS=$((ERRORS + 1))
  fi

done <<< "$STAGED"

# TypeScript type check on staged .ts files
TS_FILES=$(echo "$STAGED" | grep -E '\.(ts|tsx)$' | grep -v '\.d\.ts$' | grep -v 'node_modules/' || true)
if [[ -n "$TS_FILES" ]]; then
  # Find nearest tsconfig
  FIRST_TS=$(echo "$TS_FILES" | head -1)
  PROJ_DIR=$(dirname "$FIRST_TS")
  while [[ "$PROJ_DIR" != "/" && "$PROJ_DIR" != "." ]]; do
    [[ -f "$PROJ_DIR/tsconfig.json" ]] && break
    PROJ_DIR=$(dirname "$PROJ_DIR")
  done

  if [[ -f "$PROJ_DIR/tsconfig.json" ]]; then
    TSC_OUT=$(cd "$PROJ_DIR" && npx tsc --noEmit --pretty false 2>&1 | head -10) || true
    if [[ -n "$TSC_OUT" ]]; then
      echo "WARNING: TypeScript errors found:" >&2
      echo "$TSC_OUT" >&2
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
fi

# Summary
if [[ $ERRORS -gt 0 ]]; then
  echo "" >&2
  echo "Pre-commit: $ERRORS critical issue(s), $WARNINGS warning(s). Fix critical issues before committing." >&2
  exit 1
fi

if [[ $WARNINGS -gt 0 ]]; then
  echo "" >&2
  echo "Pre-commit: $WARNINGS warning(s). Consider fixing before committing." >&2
fi

exit 0
