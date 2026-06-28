#!/usr/bin/env bash
set -euo pipefail

# TaskCompleted hook -- sends Telegram notification when a task finishes
# Runs async so it doesn't block Claude

INPUT=$(cat)

TASK_NAME=$(echo "$INPUT" | jq -r '.task_name // .description // "unnamed task"')
TASK_STATUS=$(echo "$INPUT" | jq -r '.status // "completed"')
AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // "Claude"')

# Load Telegram credentials from .env
ENV_FILE="/home/tomakl/projects/.env"
if [[ -f "$ENV_FILE" ]]; then
  TELEGRAM_BOT_TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" | cut -d'=' -f2-)
  TELEGRAM_CHAT_ID=$(grep '^TELEGRAM_CHAT_ID=' "$ENV_FILE" | cut -d'=' -f2-)
fi

# Fallback: try Vault directly if .env is missing
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  VAULT_TOKEN_FILE="/home/user/.vault/root-token"
  if [[ -f "$VAULT_TOKEN_FILE" ]]; then
    VAULT_TOKEN=$(cat "$VAULT_TOKEN_FILE")
    VAULT_ADDR="http://127.0.0.1:8200"
    VAULT_RESPONSE=$(curl -s -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR}/v1/secret/data/services/telegram" 2>/dev/null || echo "{}")
    TELEGRAM_BOT_TOKEN=$(echo "$VAULT_RESPONSE" | jq -r '.data.data.bot_token // empty')
    TELEGRAM_CHAT_ID=$(echo "$VAULT_RESPONSE" | jq -r '.data.data.chat_id // empty')
  fi
fi

# If no credentials, exit silently (non-blocking)
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  exit 0
fi

# Build message
ICON="✅"
if [[ "$TASK_STATUS" == "failed" || "$TASK_STATUS" == "error" ]]; then
  ICON="❌"
fi

MESSAGE="${ICON} <b>Task completed</b>
<b>Task:</b> ${TASK_NAME}
<b>Status:</b> ${TASK_STATUS}
<b>Agent:</b> ${AGENT_NAME}"

# Send to Telegram (fire and forget)
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg chat_id "$TELEGRAM_CHAT_ID" \
    --arg text "$MESSAGE" \
    '{chat_id: $chat_id, text: $text, parse_mode: "HTML", disable_web_page_preview: true}')" \
  >/dev/null 2>&1 || true

exit 0
