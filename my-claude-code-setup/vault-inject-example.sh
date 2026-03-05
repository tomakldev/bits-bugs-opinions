#!/usr/bin/env bash
# Store a secret in Vault and regenerate config files.
# Replace <your-token> and <your-chat-id> with actual values.

vault kv put secret/services/telegram bot_token="<your-token>" chat_id="<your-chat-id>"
scripts/vault/inject.sh
# .env now has TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID
