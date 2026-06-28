#!/usr/bin/env bash
# MCP trust and rug-pull defense.
#
# Two protections:
# 1. TOFU: first time a tool is called, record it. Alert on genuinely new tools
#    appearing from servers already in the trust store (expansion attack).
# 2. Server tool-set audit: track which tool names each server exposes.
#    If a new tool name appears on a server that was previously stable,
#    output a system warning. Claude Code's PostToolUse logs provide the
#    audit trail; this hook provides the real-time alert.
#
# Limitation: cannot compare tool *descriptions* (not available in PreToolUse).
# Description-level rug-pull detection requires SessionStart + MCP tools/list API.

set -euo pipefail

HASH_FILE="$HOME/.claude/mcp-tool-hashes.json"
LOG_FILE="$HOME/.claude/mcp-tool-audit.log"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', ''))
except:
    print('')
" 2>/dev/null)

# Only process MCP tools
case "$TOOL_NAME" in
    mcp__*) ;;
    *) exit 0 ;;
esac

# Extract server name from mcp__server__tool pattern
SERVER_NAME=$(echo "$TOOL_NAME" | python3 -c "
import sys
t = sys.stdin.read().strip()
parts = t.split('__')
print(parts[1] if len(parts) >= 3 else 'unknown')
" 2>/dev/null)

TIMESTAMP=$(date -Iseconds)

# Initialize store if missing
if [[ ! -f "$HASH_FILE" ]]; then
    echo '{}' > "$HASH_FILE"
fi

# Check and update trust store
RESULT=$(python3 -c "
import json, sys

hash_file = '$HASH_FILE'
tool = '$TOOL_NAME'
server = '$SERVER_NAME'
ts = '$TIMESTAMP'

try:
    with open(hash_file) as f:
        db = json.load(f)
except:
    db = {}

is_new_tool = tool not in db
is_new_server = server not in [v.get('server') for v in db.values()]
server_tools = [k for k, v in db.items() if v.get('server') == server]

if is_new_tool:
    db[tool] = {
        'server': server,
        'first_seen': ts,
        'call_count': 1
    }
    with open(hash_file, 'w') as f:
        json.dump(db, f, indent=2)

    if is_new_server:
        print('FIRST_SERVER')
    else:
        print('NEW_TOOL:' + str(len(server_tools)))
else:
    db[tool]['call_count'] = db[tool].get('call_count', 0) + 1
    with open(hash_file, 'w') as f:
        json.dump(db, f, indent=2)
    print('KNOWN')
" 2>/dev/null)

# Append to audit log
echo "$TIMESTAMP TOOL=$TOOL_NAME SERVER=$SERVER_NAME STATUS=$RESULT" >> "$LOG_FILE" 2>/dev/null || true

case "$RESULT" in
    KNOWN|FIRST_SERVER)
        exit 0
        ;;
    NEW_TOOL:*)
        PREV_COUNT="${RESULT#NEW_TOOL:}"
        MSG=$(printf 'MCP: New tool %s on server %s (was %s known tools). Verify if unexpected.' \
            "$TOOL_NAME" "$SERVER_NAME" "$PREV_COUNT")
        MSG_JSON=$(printf '%s' "$MSG" | jq -Rs .)
        printf '{"systemMessage":%s}\n' "$MSG_JSON"
        ;;
    *)
        exit 0
        ;;
esac
