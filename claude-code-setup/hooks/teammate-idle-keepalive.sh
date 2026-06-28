#!/usr/bin/env bash
set -euo pipefail

# TeammateIdle hook -- prevents agent team teammates from going idle
# Returns JSON to keep the teammate working when there's still work to do

INPUT=$(cat)

AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // .teammate_name // "unknown"')
TASK_STATUS=$(echo "$INPUT" | jq -r '.task_status // "unknown"')

# If the teammate has pending work, block the idle and tell it to continue
# "unknown" means no task system was used -- let the agent go idle
if [[ "$TASK_STATUS" != "completed" && "$TASK_STATUS" != "failed" && "$TASK_STATUS" != "unknown" ]]; then
  cat <<EOF
{
  "decision": "block",
  "reason": "Teammate ${AGENT_NAME} still has work to do. Continue with your assigned task. If you are stuck, report what you've found so far and what's blocking you."
}
EOF
  exit 0
fi

# If task is done, let the teammate go idle
exit 0
