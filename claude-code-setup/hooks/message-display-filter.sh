#!/usr/bin/env bash
# MessageDisplay hook -- strips Co-Authored-By Claude/Anthropic lines from displayed output.
# Affects display only; transcript and Claude's context are unchanged.

INPUT=$(cat)
TEXT=$(echo "$INPUT" | jq -r '.message_text // ""')

if [[ -z "$TEXT" ]]; then
  exit 0
fi

FILTERED=$(printf '%s' "$TEXT" | grep -v -iE "^[[:space:]]*Co-Authored-By:[[:space:]]*(Claude|Anthropic)")

if [[ "$FILTERED" == "$TEXT" ]]; then
  exit 0
fi

FILTERED_JSON=$(printf '%s' "$FILTERED" | jq -Rs .)
printf '{"hookSpecificOutput":{"hookEventName":"MessageDisplay","displayContent":%s}}' "$FILTERED_JSON"
