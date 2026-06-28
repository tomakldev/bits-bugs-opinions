#!/usr/bin/env bash
set -euo pipefail

# PreCompact hook -- saves conversation transcript to NAS before context compression
# This preserves the full conversation history that would otherwise be lost during compaction

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
TIMESTAMP=$(date '+%Y-%m-%dT%H-%M-%S')
NAS_DIR="/mnt/nas/claude/exports/transcripts"
TRANSCRIPT_DIR="/home/tomakl/.claude/projects/-home-tomakl-projects"

# Ensure NAS directory exists
if [[ ! -d "$NAS_DIR" ]]; then
  mkdir -p "$NAS_DIR" 2>/dev/null || true
fi

# Check NAS is accessible
if [[ ! -d "/mnt/nas/claude" ]]; then
  # NAS not mounted, skip silently
  exit 0
fi

# Find the current session's JSONL transcript
TRANSCRIPT_FILE="${TRANSCRIPT_DIR}/${SESSION_ID}.jsonl"
if [[ ! -f "$TRANSCRIPT_FILE" ]]; then
  # Try to find any recent transcript
  TRANSCRIPT_FILE=$(find "$TRANSCRIPT_DIR" -name '*.jsonl' -newer "$TRANSCRIPT_DIR" -maxdepth 1 2>/dev/null | head -1 || echo "")
fi

if [[ -n "$TRANSCRIPT_FILE" && -f "$TRANSCRIPT_FILE" ]]; then
  BASENAME=$(basename "$TRANSCRIPT_FILE" .jsonl)
  DEST="${NAS_DIR}/${BASENAME}-precompact-${TIMESTAMP}.jsonl"
  cp "$TRANSCRIPT_FILE" "$DEST" 2>/dev/null || true
fi

exit 0
