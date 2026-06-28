#!/usr/bin/env bash
set -euo pipefail

# Stop hook -- extract session learnings via Claude Sonnet API
# Analyzes git activity, deduplicates against existing learnings,
# appends only genuinely new insights

INPUT=$(cat)

# Extract last_assistant_message from hook input (new field in Claude Code)
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || echo "")

# Source API key
source /home/tomakl/projects/.env 2>/dev/null || true
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  exit 0
fi

MEMORY_DIR="/home/tomakl/.claude/projects/-home-tomakl-projects/memory"
LEARNINGS_FILE="$MEMORY_DIR/session-learnings.md"
GIT_DIR="/home/tomakl/projects"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
MAX_FILE_LINES=300

# Check if there was meaningful work this session
RECENT_COMMITS=$(cd "$GIT_DIR" && git log --oneline --since="3 hours ago" 2>/dev/null | head -10 || echo "")
CHANGED_FILES=$(cd "$GIT_DIR" && git diff --name-only 2>/dev/null | head -20 || echo "")
STAGED_FILES=$(cd "$GIT_DIR" && git diff --cached --name-only 2>/dev/null | head -10 || echo "")

# Skip if nothing happened (allow if last message has substance)
if [[ -z "$RECENT_COMMITS" && -z "$CHANGED_FILES" && -z "$STAGED_FILES" && ${#LAST_MSG} -lt 100 ]]; then
  exit 0
fi

# Build session context
SESSION_CONTEXT=""
if [[ -n "$RECENT_COMMITS" ]]; then
  SESSION_CONTEXT+="Recent commits:\n$RECENT_COMMITS\n\n"
fi
if [[ -n "$CHANGED_FILES" ]]; then
  SESSION_CONTEXT+="Uncommitted changes:\n$CHANGED_FILES\n\n"
fi
if [[ -n "$STAGED_FILES" ]]; then
  SESSION_CONTEXT+="Staged files:\n$STAGED_FILES\n\n"
fi

DIFF_STAT=$(cd "$GIT_DIR" && git diff --stat 2>/dev/null | tail -5 || echo "")
if [[ -n "$DIFF_STAT" ]]; then
  SESSION_CONTEXT+="Diff summary:\n$DIFF_STAT\n"
fi

# Include last assistant message for richer context (truncate to 800 chars)
if [[ -n "$LAST_MSG" ]]; then
  SESSION_CONTEXT+="Last assistant message:\n${LAST_MSG:0:800}\n"
fi

# Read recent learnings for dedup (last 80 lines)
RECENT_LEARNINGS=$(tail -80 "$LEARNINGS_FILE" 2>/dev/null || echo "")

# Read memory index for context
CURRENT_MEMORY=$(head -80 "$MEMORY_DIR/MEMORY.md" 2>/dev/null || echo "")

# Call Claude Sonnet API
RESPONSE=$(curl -s --noproxy '*' --max-time 45 \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  https://api.anthropic.com/v1/messages \
  -d "$(jq -nc \
    --arg session "$SESSION_CONTEXT" \
    --arg memory "$CURRENT_MEMORY" \
    --arg recent "$RECENT_LEARNINGS" \
    '{
      model: "claude-sonnet-4-5-20250514",
      max_tokens: 250,
      messages: [{
        role: "user",
        content: ("You extract reusable technical knowledge from a developer session. You output ONLY raw bullet points or the word NONE. No headers, no commentary, no markdown formatting.\n\nSession git activity:\n" + $session + "\n\nAlready in persistent memory (NEVER repeat):\n" + $memory + "\n\nRecent learnings already captured (NEVER repeat):\n" + $recent + "\n\nExtract 0-2 learnings that meet ALL of these criteria:\n- It is a reusable pattern, workaround, or technical insight\n- It would help a future session avoid a mistake or save time\n- It is NOT already covered in memory or recent learnings above\n- It describes WHY something works, not WHAT files changed\n\nExamples of GOOD learnings:\n- Cloudflare aggressively caches images by URL; rename the file to force cache bust\n- systemd user services need loginctl enable-linger to survive logout\n\nExamples of BAD learnings (never output these):\n- Blog post formatting was updated with new month names\n- Polish diacritics are important for user-facing content\n- Hook script was modified to improve learning extraction\n\nOutput format: bare bullet lines starting with \"- \" or the single word NONE. Nothing else.")
      }]
    }')" 2>/dev/null || echo "")

# Extract text from API response
LEARNINGS=$(echo "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null || echo "")

# Skip if empty or API failed
if [[ -z "$LEARNINGS" ]]; then
  exit 0
fi

# Strip NONE and blank lines, keep only bullet lines
LEARNINGS=$(echo "$LEARNINGS" | grep '^- ' || true)

if [[ -z "$LEARNINGS" ]]; then
  exit 0
fi

# Client-side dedup: skip bullets whose core content already exists
NEW_LEARNINGS=""
while IFS= read -r line; do
  # Extract key phrase (first 50 chars after "- ", lowercased)
  phrase=$(echo "$line" | sed 's/^- //' | cut -c1-50 | tr '[:upper:]' '[:lower:]')
  if [[ -n "$phrase" ]] && ! echo "$RECENT_LEARNINGS" | grep -qiF "$phrase" 2>/dev/null; then
    NEW_LEARNINGS+="$line"$'\n'
  fi
done <<< "$LEARNINGS"

NEW_LEARNINGS=$(echo "$NEW_LEARNINGS" | sed '/^$/d')

if [[ -z "$NEW_LEARNINGS" ]]; then
  exit 0
fi

# Append to learnings file
{
  echo ""
  echo "## $TIMESTAMP"
  echo "$NEW_LEARNINGS"
} >> "$LEARNINGS_FILE" 2>/dev/null || true

# Rotate: keep only last MAX_FILE_LINES
if [[ -f "$LEARNINGS_FILE" ]]; then
  FILE_LINES=$(wc -l < "$LEARNINGS_FILE")
  if [[ "$FILE_LINES" -gt "$MAX_FILE_LINES" ]]; then
    tail -"$MAX_FILE_LINES" "$LEARNINGS_FILE" > "${LEARNINGS_FILE}.tmp" 2>/dev/null
    mv "${LEARNINGS_FILE}.tmp" "$LEARNINGS_FILE" 2>/dev/null || true
  fi
fi

exit 0
