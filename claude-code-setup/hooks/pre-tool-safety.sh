#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook -- second-layer safety net
# Catches dangerous patterns that might slip through auto-approved permissions
# (e.g., destructive commands inside auto-approved SSH, writes to sensitive files)
#
# Two layers:
#   1. Declarative YAML rules (.claude/rules/agent-safety-rules.yaml)
#   2. Hardcoded bash checks (legacy, catches edge cases)

INPUT=$(cat)


TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty')

# --- Layer 1: Declarative YAML rules ---
RULES_FILE="/home/tomakl/projects/.claude/rules/agent-safety-rules.yaml"
if [[ -f "$RULES_FILE" ]] && command -v yq &>/dev/null; then
  set +e
  RULE_COUNT=$(yq '.rules | length' "$RULES_FILE" 2>/dev/null || echo 0)

  for ((i=0; i<RULE_COUNT; i++)); do
    RULE_TRIGGER=$(yq -r ".rules[$i].trigger" "$RULES_FILE")

    # Check if rule applies to this tool
    if [[ "$TOOL_NAME" != "$RULE_TRIGGER" ]]; then
      continue
    fi

    RULE_NAME=$(yq -r ".rules[$i].name" "$RULES_FILE")
    RULE_ACTION=$(yq -r ".rules[$i].enforce" "$RULES_FILE")
    RULE_REASON=$(yq -r ".rules[$i].reason" "$RULES_FILE")

    # Check predicates
    MATCHED=false

    # command_matches predicate (for Bash tool)
    CMD_PATTERN=$(yq -r ".rules[$i].check.command_matches" "$RULES_FILE" 2>/dev/null)
    if [[ -n "$CMD_PATTERN" && "$CMD_PATTERN" != "null" && "$TOOL_NAME" == "Bash" ]]; then
      BASH_CMD_CHECK=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
      if echo "$BASH_CMD_CHECK" | grep -qP "$CMD_PATTERN" 2>/dev/null; then
        MATCHED=true
      fi
    fi

    # input_matches predicate (for MCP tools)
    INPUT_FIELD=$(yq -r ".rules[$i].check.input_matches | keys | .[0]" "$RULES_FILE" 2>/dev/null)
    if [[ -n "$INPUT_FIELD" && "$INPUT_FIELD" != "null" ]]; then
      INPUT_PATTERN=$(yq -r ".rules[$i].check.input_matches.$INPUT_FIELD" "$RULES_FILE" 2>/dev/null)
      ACTUAL_VALUE=$(echo "$INPUT" | jq -r ".tool_input.$INPUT_FIELD // empty" 2>/dev/null)
      if [[ -n "$INPUT_PATTERN" && "$INPUT_PATTERN" != "null" ]] && echo "$ACTUAL_VALUE" | grep -qP "$INPUT_PATTERN" 2>/dev/null; then
        MATCHED=true
      fi
    fi

    # always predicate
    ALWAYS=$(yq -r ".rules[$i].check.always" "$RULES_FILE" 2>/dev/null)
    if [[ "$ALWAYS" == "true" ]]; then
      MATCHED=true
    fi

    if [[ "$MATCHED" == "true" ]]; then
      case "$RULE_ACTION" in
        block)
          echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"[$RULE_NAME] $RULE_REASON\"}}"
          exit 0
          ;;
        inspect)
          # Let the tool call through to Claude's normal permission prompt
          # by not emitting any decision (user sees the standard approve/deny dialog)
          exit 0
          ;;
        reprompt)
          echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"[$RULE_NAME] $RULE_REASON -- justify this action before proceeding\"}}"
          exit 0
          ;;
      esac
    fi
  done
  set -e
fi

# --- Bash command inspection ---
if [[ "$TOOL_NAME" == "Bash" ]]; then
  BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

  # Block fork bombs
  if [[ "$BASH_CMD" =~ :\(\)\{.*\} ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: fork bomb pattern detected"}}'
    exit 0
  fi

  # Block raw disk writes
  if [[ "$BASH_CMD" =~ \>/dev/sd[a-z] ]] || [[ "$BASH_CMD" =~ dd[[:space:]]+.*of=/dev/sd ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: raw disk write detected"}}'
    exit 0
  fi

  # Block mkfs (filesystem format)
  if [[ "$BASH_CMD" =~ mkfs\. ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: mkfs would format a partition"}}'
    exit 0
  fi

  # Block chmod 777 recursively
  if [[ "$BASH_CMD" =~ chmod[[:space:]]+-[Rr][[:space:]]+777 ]] || [[ "$BASH_CMD" =~ chmod[[:space:]]+777[[:space:]]+-[Rr] ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: recursive chmod 777 is a security risk"}}'
    exit 0
  fi

  # Block docker system prune -a (removes everything)
  if [[ "$BASH_CMD" =~ docker[[:space:]]+system[[:space:]]+prune[[:space:]]+-a ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: docker system prune -a removes all unused images and volumes"}}'
    exit 0
  fi

  # Block rm -rf on system paths (local commands)
  if [[ "$BASH_CMD" =~ rm[[:space:]]+-r[f]?[[:space:]] ]] || [[ "$BASH_CMD" =~ rm[[:space:]]+-fr[[:space:]] ]]; then
    # Allow safe paths: /tmp, /home/tomakl, project dirs
    if [[ "$BASH_CMD" =~ rm[[:space:]]+-r[f]?[[:space:]]+/(var|usr|opt|srv|lib|boot|snap|root|sys|proc|run|sbin|bin|etc) ]] || \
       [[ "$BASH_CMD" =~ rm[[:space:]]+-fr[[:space:]]+/(var|usr|opt|srv|lib|boot|snap|root|sys|proc|run|sbin|bin|etc) ]]; then
      # Exit without output = falls through to normal permission prompt
      # User can approve or deny interactively
      exit 2
    fi
  fi

  # Inspect SSH commands for nested destructive operations
  if [[ "$BASH_CMD" =~ ^ssh[[:space:]] ]]; then
    # Extract the remote command (everything after the hostname)
    REMOTE_CMD=$(echo "$BASH_CMD" | sed -E 's/^ssh\s+[^ ]+\s+"?//' | sed 's/"$//')

    if [[ "$REMOTE_CMD" =~ rm[[:space:]]+-rf[[:space:]]+/ ]] && ! [[ "$REMOTE_CMD" =~ rm[[:space:]]+-rf[[:space:]]+/home ]] && ! [[ "$REMOTE_CMD" =~ rm[[:space:]]+-rf[[:space:]]+/tmp ]]; then
      echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: SSH command contains dangerous rm -rf on root paths"}}'
      exit 0
    fi

    if [[ "$REMOTE_CMD" =~ mkfs\. ]] || [[ "$REMOTE_CMD" =~ \>/dev/sd ]]; then
      echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: SSH command contains disk-destructive operation"}}'
      exit 0
    fi
  fi

  # Block SQL destructive operations without WHERE
  if [[ "$BASH_CMD" =~ (DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|TRUNCATE[[:space:]]+TABLE) ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: SQL DROP/TRUNCATE detected -- confirm with user first"}}'
    exit 0
  fi

  if [[ "$BASH_CMD" =~ DELETE[[:space:]]+FROM ]] && ! [[ "$BASH_CMD" =~ WHERE ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: SQL DELETE without WHERE clause"}}'
    exit 0
  fi

  # --- Argument injection defense (Trail of Bits pattern) ---
  # Block eval/source with variable expansion (RCE vector)
  if [[ "$BASH_CMD" =~ eval[[:space:]] ]] || [[ "$BASH_CMD" =~ ^source[[:space:]] ]] || [[ "$BASH_CMD" =~ \;[[:space:]]*source[[:space:]] ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: eval/source detected -- high RCE risk via argument injection"}}'
    exit 0
  fi

  # Block backtick command substitution in arguments (legacy shell injection)
  # Ignore backticks inside single-quoted strings or markdown
  STRIPPED_SINGLES=$(echo "$BASH_CMD" | sed "s/'[^']*'//g")
  if echo "$STRIPPED_SINGLES" | grep -qP '(?<!\\)`[^`]+`'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: backtick command substitution detected -- use $(cmd) syntax and ensure it is intentional"}}'
    exit 0
  fi

  # Block path traversal beyond sandbox (symlink escape)
  # Extract file path arguments and resolve them
  for path_arg in $(echo "$BASH_CMD" | grep -oP '(?:^|\s)(/[^\s;|&>]+)' | tr -d ' '); do
    if [[ "$path_arg" =~ \.\. ]]; then
      RESOLVED=$(realpath -m "$path_arg" 2>/dev/null || echo "$path_arg")
      # Block traversal into /etc, /root, /boot, /proc, /sys
      if [[ "$RESOLVED" =~ ^/(etc|root|boot|proc|sys)/ ]]; then
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Blocked: path traversal resolves to sensitive directory: $RESOLVED\"}}"
        exit 0
      fi
    fi
  done

  # Block reading sensitive system files
  if [[ "$BASH_CMD" =~ /etc/shadow ]] || [[ "$BASH_CMD" =~ /etc/passwd ]] && [[ "$BASH_CMD" =~ (cat|head|tail|less|more|grep|awk|sed) ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: reading sensitive system auth files"}}'
    exit 0
  fi

  # Block find commands scanning for credentials
  if [[ "$BASH_CMD" =~ find[[:space:]] ]] && [[ "$BASH_CMD" =~ \.(pem|key|p12|pfx|jks|keystore)\" ]] || [[ "$BASH_CMD" =~ -name.*id_rsa ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: scanning for credential/key files is not allowed"}}'
    exit 0
  fi

  # Block tee/redirect to files outside sandbox
  if echo "$BASH_CMD" | grep -qP '\|\s*tee\s+/(?!home/tomakl|tmp|dev/null|dev/stdout|dev/stderr)'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: tee redirect to system path outside sandbox"}}'
    exit 0
  fi

  # Argument injection: git --exec
  if [[ "$BASH_CMD" =~ git[[:space:]]+(show|log|rebase|am|bisect)[[:space:]] ]] && [[ "$BASH_CMD" =~ --exec ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: git --exec enables arbitrary command execution"}}'
    exit 0
  fi

  # Argument injection: rg --pre
  if [[ "$BASH_CMD" =~ (rg|ripgrep)[[:space:]] ]] && [[ "$BASH_CMD" =~ --pre[[:space:]] ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: rg --pre runs arbitrary commands on files"}}'
    exit 0
  fi

  # Argument injection: go test -exec
  if [[ "$BASH_CMD" =~ go[[:space:]]+test ]] && [[ "$BASH_CMD" =~ -exec ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: go test -exec replaces test binary"}}'
    exit 0
  fi

  # Argument injection: find -exec rm
  if [[ "$BASH_CMD" =~ find[[:space:]] ]] && [[ "$BASH_CMD" =~ -exec[[:space:]] ]] && [[ "$BASH_CMD" =~ rm[[:space:]] ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: find -exec rm is dangerous"}}'
    exit 0
  fi

  # Argument injection: xargs with destructive commands without -0
  if [[ "$BASH_CMD" =~ \|[[:space:]]*xargs[[:space:]] ]] && ! [[ "$BASH_CMD" =~ xargs[[:space:]]+-0 ]] && ! [[ "$BASH_CMD" =~ xargs[[:space:]]+-d ]]; then
    if [[ "$BASH_CMD" =~ xargs[[:space:]].*(rm|mv|chmod|chown) ]]; then
      echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: xargs with destructive cmd without -0 risks argument injection"}}'
      exit 0
    fi
  fi
fi

# --- Write/Edit to sensitive files ---
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" ]]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

  # Block .env file modifications (per CLAUDE.md rules)
  if [[ "$FILE_PATH" =~ \.env$ ]] || [[ "$FILE_PATH" =~ \.env\. ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: .env files are managed via Vault -- use scripts/vault/inject.sh"}}'
    exit 0
  fi

  # Block /etc/ writes
  if [[ "$FILE_PATH" =~ ^/etc/ ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: writing to /etc/ requires explicit user confirmation"}}'
    exit 0
  fi

  # Block credentials/key files
  if [[ "$FILE_PATH" =~ \.pem$ ]] || [[ "$FILE_PATH" =~ \.key$ ]] || [[ "$FILE_PATH" =~ id_rsa ]] || [[ "$FILE_PATH" =~ credentials\.json ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: writing to credential/key files is not allowed"}}'
    exit 0
  fi
fi

# --- Secret-leak detection ---
# Scan tool input for credential patterns before any tool call
TOOL_INPUT_STR=$(echo "$INPUT" | jq -r '.tool_input | tostring // empty')

# AWS access keys (AKIA...)
if [[ "$TOOL_INPUT_STR" =~ AKIA[0-9A-Z]{16} ]]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: AWS access key detected in tool input -- remove credential before proceeding"}}'
  exit 0
fi

# Vault tokens (hvs.)
if [[ "$TOOL_INPUT_STR" =~ hvs\.[a-zA-Z0-9_-]{24,} ]]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: Vault token detected in tool input -- never send tokens through tool calls"}}'
  exit 0
fi

# Generic bearer/auth tokens in headers
if [[ "$TOOL_INPUT_STR" =~ Bearer[[:space:]]+[a-zA-Z0-9_-]{20,} ]]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: Bearer token detected in tool input -- use environment variables instead"}}'
  exit 0
fi

# Private keys (PEM headers)
if echo "$TOOL_INPUT_STR" | grep -qP '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: private key material detected in tool input"}}'
  exit 0
fi

# GitHub/GitLab personal access tokens
if [[ "$TOOL_INPUT_STR" =~ (ghp_|glpat-|github_pat_)[a-zA-Z0-9_]{16,} ]]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: GitHub/GitLab token detected in tool input"}}'
  exit 0
fi

# Generic password=/api_key= patterns in plaintext
if echo "$TOOL_INPUT_STR" | grep -qP '(password|api_key|apikey|secret_key|access_token)\s*=\s*[a-zA-Z0-9_/+=]{16,}'; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: plaintext credential pattern detected in tool input -- use Vault references"}}'
  exit 0
fi

# No issues found -- allow
exit 0
