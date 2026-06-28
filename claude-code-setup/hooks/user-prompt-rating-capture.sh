#!/usr/bin/env bash
set -euo pipefail

# UserPromptSubmit hook -- captures explicit ratings and sentiment signals
# Inspired by PAI's signal capture system
# Detects: bare numbers (1-10), praise, criticism, corrections
# Stores in ratings.jsonl for pattern analysis

INPUT=$(cat)

USER_MSG=$(echo "$INPUT" | jq -r '.user_message // empty')

# Skip empty or very short messages
if [[ ${#USER_MSG} -lt 1 ]]; then
  exit 0
fi

RATINGS_FILE="/home/tomakl/.claude/projects/-home-tomakl-projects/memory/ratings.jsonl"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Detect explicit numeric ratings (bare "7", "8 - great", "3/10", "rating: 9")
RATING=""
RATING_TYPE=""

# Bare number at start of message (1-10)
if echo "$USER_MSG" | grep -qP '^\s*([1-9]|10)\s*($|[\s,.\-:!])'; then
  RATING=$(echo "$USER_MSG" | grep -oP '^\s*\K([1-9]|10)')
  RATING_TYPE="explicit_numeric"
fi

# "X/10" or "X / 10" pattern
if [[ -z "$RATING" ]] && echo "$USER_MSG" | grep -qP '\b([1-9]|10)\s*/\s*10\b'; then
  RATING=$(echo "$USER_MSG" | grep -oP '\b\K([1-9]|10)(?=\s*/\s*10)')
  RATING_TYPE="explicit_scale"
fi

# "rating: X" or "score: X" pattern
if [[ -z "$RATING" ]] && echo "$USER_MSG" | grep -qiP '(rating|score)\s*:?\s*([1-9]|10)\b'; then
  RATING=$(echo "$USER_MSG" | grep -oiP '(rating|score)\s*:?\s*\K([1-9]|10)')
  RATING_TYPE="explicit_labeled"
fi

# Detect sentiment signals (no numeric rating but clear feedback)
SENTIMENT=""
if [[ -z "$RATING" ]]; then
  MSG_LOWER=$(echo "$USER_MSG" | tr '[:upper:]' '[:lower:]')

  # Strong positive
  if echo "$MSG_LOWER" | grep -qP '(great work|perfect|excellent|awesome|exactly what|nailed it|love it|well done)'; then
    SENTIMENT="positive_strong"
    RATING="9"
    RATING_TYPE="implicit_sentiment"
  # Mild positive
  elif echo "$MSG_LOWER" | grep -qP '(good|nice|thanks|works|correct|right)' && ! echo "$MSG_LOWER" | grep -qP '(not good|not right|not correct|no good)'; then
    SENTIMENT="positive_mild"
    RATING="7"
    RATING_TYPE="implicit_sentiment"
  # Strong negative
  elif echo "$MSG_LOWER" | grep -qP '(wrong|broken|terrible|awful|useless|completely wrong|that.s not|you broke|messed up|screwed up)'; then
    SENTIMENT="negative_strong"
    RATING="2"
    RATING_TYPE="implicit_sentiment"
  # Mild negative
  elif echo "$MSG_LOWER" | grep -qP '(not quite|close but|almost|try again|redo|fix this|that.s off)'; then
    SENTIMENT="negative_mild"
    RATING="4"
    RATING_TYPE="implicit_sentiment"
  fi
fi

# Only log if we detected a rating or sentiment
if [[ -n "$RATING" ]]; then
  # Truncate message for storage (first 200 chars)
  MSG_PREVIEW=$(echo "$USER_MSG" | head -c 200 | tr '\n' ' ')

  # Write JSONL entry
  jq -nc \
    --arg ts "$TIMESTAMP" \
    --arg rating "$RATING" \
    --arg type "$RATING_TYPE" \
    --arg sentiment "${SENTIMENT:-none}" \
    --arg msg "$MSG_PREVIEW" \
    '{timestamp: $ts, rating: ($rating | tonumber), type: $type, sentiment: $sentiment, message: $msg}' \
    >> "$RATINGS_FILE" 2>/dev/null || true
fi

exit 0
