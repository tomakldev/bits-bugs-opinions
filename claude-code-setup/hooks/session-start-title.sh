#!/usr/bin/env bash
# SessionStart hook:
# - Every day: sets session title to "branch · YYYY-MM-DD"
# - Monday (first session only): injects additionalContext to auto-fetch weekly on-call schedules

INPUT=$(cat)
SOURCE=$(echo "$INPUT" | jq -r '.source // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

if [[ "$SOURCE" != "startup" && "$SOURCE" != "resume" ]]; then
  exit 0
fi

BRANCH=$(cd "$CWD" 2>/dev/null && git branch --show-current 2>/dev/null || echo "")
DATE=$(date '+%Y-%m-%d')
DOW=$(date +%u)   # 1 = Monday
CW=$(date +%V)

if [[ -n "$BRANCH" ]]; then
  TITLE="${BRANCH} · ${DATE}"
else
  TITLE="${DATE}"
fi

# On Mondays, inject on-call check instruction — but only once per day (flag file guard)
if [[ "$DOW" == "1" ]]; then
  TITLE="${BRANCH:-projects} · CW${CW} Monday"
  FLAG="/tmp/oncall-check-${DATE}"

  if [[ ! -f "$FLAG" ]]; then
    touch "$FLAG"

    CONTEXT="Today is Monday CW${CW}. Before responding to the first user message, fetch and display this week's on-call schedule from Confluence. Query these pages:
- MIM on-call rotation: page ID 1885700100 (DSAMSPL space)
- YEAR 2026 weekly schedule (Ticket Master + Patching Master): page ID 2958230078
- Regular on-call (Apps + Windows): search Confluence for 'AMS PL Team On-Call Duty'

Display a compact table:
Role | Person | Notes

Roles to show: MIM on-call, Ticket Master, Patching Master, Regular on-call (Apps), Regular on-call (Windows).
If any role is you (Tomasz Lech), highlight it."

    CONTEXT_JSON=$(printf '%s' "$CONTEXT" | jq -Rs .)
    TITLE_JSON=$(printf '%s' "$TITLE" | jq -Rs .)
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","sessionTitle":%s,"additionalContext":%s}}' \
      "$TITLE_JSON" "$CONTEXT_JSON"
    exit 0
  fi
fi

TITLE_JSON=$(printf '%s' "$TITLE" | jq -Rs .)
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","sessionTitle":%s}}' "$TITLE_JSON"
