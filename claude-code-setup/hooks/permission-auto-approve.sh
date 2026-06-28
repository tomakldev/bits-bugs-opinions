#!/usr/bin/env bash
set -euo pipefail

# PermissionRequest auto-approve hook
# Reads tool info from stdin JSON, returns approval/denial decision
# Exit 0 = no decision (normal flow), stdout JSON = explicit decision

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty')

# Extract bash command if present
BASH_CMD=""
if [[ "$TOOL_NAME" == "Bash" ]]; then
  BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
fi

# --- DENY dangerous patterns first ---
if [[ "$TOOL_NAME" == "Bash" && -n "$BASH_CMD" ]]; then
  # Block rm -rf /
  if [[ "$BASH_CMD" =~ rm[[:space:]]+-rf[[:space:]]+/ ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","reason":"Blocked: rm -rf with root path is too dangerous"}}}'
    exit 0
  fi
  # Block force push
  if [[ "$BASH_CMD" =~ git[[:space:]]+push[[:space:]]+--force ]] || [[ "$BASH_CMD" =~ git[[:space:]]+push[[:space:]]+-f[[:space:]] ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","reason":"Blocked: force push requires explicit user approval via prompt"}}}'
    exit 0
  fi
  # Block git reset --hard
  if [[ "$BASH_CMD" =~ git[[:space:]]+reset[[:space:]]+--hard ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","reason":"Blocked: git reset --hard can destroy uncommitted work"}}}'
    exit 0
  fi
  # Block sudo rm
  if [[ "$BASH_CMD" =~ sudo[[:space:]]+rm ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","reason":"Blocked: sudo rm requires explicit user confirmation"}}}'
    exit 0
  fi

  # --- DENY destructive Azure operations ---
  if [[ "$BASH_CMD" =~ az[[:space:]]+webapp[[:space:]]+(restart|stop|delete|swap) ]] || \
     [[ "$BASH_CMD" =~ az[[:space:]]+webapp[[:space:]]+config[[:space:]]+set ]] || \
     [[ "$BASH_CMD" =~ az[[:space:]]+webapp[[:space:]]+deployment[[:space:]]+slot[[:space:]]+swap ]] || \
     [[ "$BASH_CMD" =~ az[[:space:]]+network[[:space:]]+nsg[[:space:]]+rule[[:space:]]+(create|delete|update) ]] || \
     [[ "$BASH_CMD" =~ az[[:space:]]+storage[[:space:]]+account[[:space:]]+(delete|update) ]] || \
     [[ "$BASH_CMD" =~ az[[:space:]]+resource[[:space:]]+delete ]] || \
     [[ "$BASH_CMD" =~ az[[:space:]]+group[[:space:]]+delete ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","reason":"Blocked: destructive Azure operation -- get explicit user approval first"}}}'
    exit 0
  fi

  # --- DENY destructive AWS operations ---
  if [[ "$BASH_CMD" =~ aws[[:space:]]+ec2[[:space:]]+(terminate-instances|stop-instances|modify-instance-attribute) ]] || \
     [[ "$BASH_CMD" =~ aws[[:space:]]+ec2[[:space:]]+(authorize-security-group|revoke-security-group|delete-security-group|create-security-group) ]] || \
     [[ "$BASH_CMD" =~ aws[[:space:]]+s3[[:space:]]+(rm|rb) ]] || \
     [[ "$BASH_CMD" =~ aws[[:space:]]+s3api[[:space:]]+(delete-bucket|put-bucket-policy|delete-bucket-policy|put-public-access-block) ]] || \
     [[ "$BASH_CMD" =~ aws[[:space:]]+rds[[:space:]]+(delete-db|modify-db|stop-db|reboot-db) ]] || \
     [[ "$BASH_CMD" =~ aws[[:space:]]+iam[[:space:]]+(delete-|create-|put-|attach-|detach-) ]] || \
     [[ "$BASH_CMD" =~ aws[[:space:]]+lambda[[:space:]]+(delete-function|update-function) ]] || \
     [[ "$BASH_CMD" =~ aws[[:space:]]+ec2[[:space:]]+delete-(vpc|subnet|nat-gateway|route|vpc-endpoints) ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","reason":"Blocked: destructive AWS operation -- get explicit user approval first"}}}'
    exit 0
  fi

  # --- DENY destructive K8s operations via Azure Arc SSH ---
  if [[ "$BASH_CMD" =~ kubectl[[:space:]]+(delete|scale|apply|patch|replace|edit|drain|cordon|taint) ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","reason":"Blocked: destructive kubectl operation -- get explicit user approval first"}}}'
    exit 0
  fi

  # --- DENY destructive UFW changes ---
  if [[ "$BASH_CMD" =~ ufw[[:space:]]+(allow|deny|reject|delete|reset|disable|insert) ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","reason":"Blocked: UFW rule change -- get explicit user approval first"}}}'
    exit 0
  fi

  # --- DENY service restarts on remote servers ---
  if [[ "$BASH_CMD" =~ systemctl[[:space:]]+(restart|stop|disable|mask) ]] || \
     [[ "$BASH_CMD" =~ service[[:space:]]+[a-z].*[[:space:]]+(restart|stop) ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","reason":"Blocked: service restart/stop -- get explicit user approval first"}}}'
    exit 0
  fi
fi

# --- ALLOW known safe patterns ---

# Read-only tools always safe
case "$TOOL_NAME" in
  Read|Glob|Grep|ToolSearch)
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Read-only tool auto-approved"}}}'
    exit 0
    ;;
esac

# Safe bash commands
if [[ "$TOOL_NAME" == "Bash" && -n "$BASH_CMD" ]]; then
  # Read-only git
  if [[ "$BASH_CMD" =~ ^git[[:space:]]+(status|diff|log|branch|show|remote|tag|stash\ list) ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Read-only git command auto-approved"}}}'
    exit 0
  fi
  # Vault reads
  if [[ "$BASH_CMD" =~ ^VAULT_TOKEN=.*vault[[:space:]]+kv[[:space:]]+get ]] || [[ "$BASH_CMD" =~ vault[[:space:]]+kv[[:space:]]+get ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Vault read auto-approved"}}}'
    exit 0
  fi
  # ls, pwd, which, command -v, echo, cat (info gathering)
  if [[ "$BASH_CMD" =~ ^(ls|pwd|which|command[[:space:]]+-v|echo|cat[[:space:]]) ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Info-gathering command auto-approved"}}}'
    exit 0
  fi
  # clip script
  if [[ "$BASH_CMD" =~ /home/tomakl/projects/scripts/clip ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Clipboard copy auto-approved"}}}'
    exit 0
  fi
  # gemini-image script
  if [[ "$BASH_CMD" =~ /home/tomakl/projects/scripts/gemini-image\.sh ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Gemini image generation auto-approved"}}}'
    exit 0
  fi
  # fabric binary (Gemini free tier, read-only AI patterns)
  if [[ "$BASH_CMD" =~ /home/tomakl/\.local/bin/fabric ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Fabric AI pattern auto-approved"}}}'
    exit 0
  fi
  # source .env (loading environment variables for scripts)
  if [[ "$BASH_CMD" =~ ^source[[:space:]]+/home/tomakl/projects/\.env ]] || [[ "$BASH_CMD" =~ ^\.[[:space:]]+/home/tomakl/projects/\.env ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Source project .env auto-approved"}}}'
    exit 0
  fi
  # gws CLI (Google Workspace -- replaces Gmail/Calendar MCP)
  if [[ "$BASH_CMD" =~ ^gws[[:space:]] ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Google Workspace CLI auto-approved"}}}'
    exit 0
  fi
  # yt-dlp (YouTube transcript fetching for youtube-summary skill)
  if [[ "$BASH_CMD" =~ ^yt-dlp[[:space:]] ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"YouTube transcript fetch auto-approved"}}}'
    exit 0
  fi
  # base64 decode (used by gemini-image response processing)
  if [[ "$BASH_CMD" =~ ^base64[[:space:]] ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Base64 decode auto-approved"}}}'
    exit 0
  fi
  # file/stat/wc (info gathering, used by skills)
  if [[ "$BASH_CMD" =~ ^(file|stat|wc|du|df|uname|hostname|date|id|whoami|env|printenv)[[:space:]] ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Info-gathering command auto-approved"}}}'
    exit 0
  fi
  # jq, yq on files
  if [[ "$BASH_CMD" =~ ^(jq|yq)[[:space:]] ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"JSON/YAML query auto-approved"}}}'
    exit 0
  fi
  # gh pr/issue list/view (read-only GitHub)
  if [[ "$BASH_CMD" =~ ^gh[[:space:]]+(pr|issue)[[:space:]]+(list|view|status|checks) ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Read-only GitHub CLI auto-approved"}}}'
    exit 0
  fi
  # docker/docker compose ps, logs, inspect (read-only)
  if [[ "$BASH_CMD" =~ ^(docker|docker\ compose)[[:space:]]+(ps|logs|inspect|images|stats|top|port) ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Read-only Docker command auto-approved"}}}'
    exit 0
  fi
  # ssh commands (remote servers)
  if [[ "$BASH_CMD" =~ ^ssh[[:space:]] ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"SSH command auto-approved"}}}'
    exit 0
  fi
  # Read-only AWS CLI commands
  if [[ "$BASH_CMD" =~ ^aws[[:space:]]+(sts|ec2|s3|s3api|lambda|cloudwatch|logs|rds|iam|ce|ecs|eks|route53|elb|elbv2|sns|sqs|ssm)[[:space:]]+(get-|describe-|list-|show|ls) ]] || \
     [[ "$BASH_CMD" =~ ^aws[[:space:]]+sts[[:space:]]+get-caller-identity ]] || \
     [[ "$BASH_CMD" =~ ^aws[[:space:]]+s3[[:space:]]+ls ]] || \
     [[ "$BASH_CMD" =~ ^aws[[:space:]]+configure[[:space:]]+list ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Read-only AWS CLI command auto-approved"}}}'
    exit 0
  fi
  # Read-only Azure CLI commands
  if [[ "$BASH_CMD" =~ ^az[[:space:]]+(account|webapp|network|storage|monitor|resource|group|ssh)[[:space:]]+(show|list|get|display) ]] || \
     [[ "$BASH_CMD" =~ ^az[[:space:]]+account[[:space:]]+show ]] || \
     [[ "$BASH_CMD" =~ ^az[[:space:]]+webapp[[:space:]]+(show|list) ]] || \
     [[ "$BASH_CMD" =~ ^az[[:space:]]+webapp[[:space:]]+(deployment[[:space:]]+slot[[:space:]]+list|vnet-integration[[:space:]]+list|identity[[:space:]]+show|log[[:space:]]+tail) ]] || \
     [[ "$BASH_CMD" =~ ^az[[:space:]]+monitor[[:space:]]+(activity-log|app-insights|metrics)[[:space:]]+list ]] || \
     [[ "$BASH_CMD" =~ ^az[[:space:]]+monitor[[:space:]]+app-insights[[:space:]]+query ]] || \
     [[ "$BASH_CMD" =~ ^az[[:space:]]+network[[:space:]]+nsg[[:space:]]+list ]] || \
     [[ "$BASH_CMD" =~ ^az[[:space:]]+storage[[:space:]]+account[[:space:]]+list ]] || \
     [[ "$BASH_CMD" =~ ^az[[:space:]]+ssh[[:space:]]+arc ]] || \
     [[ "$BASH_CMD" =~ ^az[[:space:]]+efs[[:space:]]+describe ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Read-only Azure CLI command auto-approved"}}}'
    exit 0
  fi
  # Vault reads via curl (API access)
  if [[ "$BASH_CMD" =~ curl.*127\.0\.0\.1:8200/v1/secret/data/ ]] && [[ ! "$BASH_CMD" =~ (-X[[:space:]]+POST|-X[[:space:]]+PUT|-X[[:space:]]+DELETE|-d[[:space:]]) ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Vault read via curl auto-approved"}}}'
    exit 0
  fi
fi

# Safe MCP tools (read-only)
case "$TOOL_NAME" in
  mcp__tavily__*|mcp__claude_ai_Tavily__*)
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Tavily search auto-approved"}}}'
    exit 0
    ;;
  mcp__context7__*)
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Context7 docs auto-approved"}}}'
    exit 0
    ;;
  mcp__filesystem__read_file|mcp__filesystem__read_text_file|mcp__filesystem__read_media_file|mcp__filesystem__read_multiple_files|mcp__filesystem__list_directory|mcp__filesystem__list_directory_with_sizes|mcp__filesystem__directory_tree|mcp__filesystem__search_files|mcp__filesystem__get_file_info|mcp__filesystem__list_allowed_directories)
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Read-only filesystem MCP auto-approved"}}}'
    exit 0
    ;;
  mcp__atlassian__search|mcp__atlassian__searchConfluenceUsingCql|mcp__atlassian__searchJiraIssuesUsingJql|mcp__atlassian__getConfluencePage|mcp__atlassian__getConfluenceSpaces|mcp__atlassian__getPagesInConfluenceSpace|mcp__atlassian__getJiraIssue|mcp__atlassian__getVisibleJiraProjects|mcp__atlassian__getJiraProjectIssueTypesMetadata|mcp__atlassian__atlassianUserInfo|mcp__atlassian__getAccessibleAtlassianResources|mcp__atlassian__getTransitionsForJiraIssue)
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Read-only Atlassian MCP auto-approved"}}}'
    exit 0
    ;;
  mcp__rube__RUBE_SEARCH_TOOLS|mcp__rube__RUBE_GET_TOOL_SCHEMAS|mcp__rube__RUBE_FIND_RECIPE|mcp__rube__RUBE_GET_RECIPE_DETAILS)
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Read-only Rube MCP auto-approved"}}}'
    exit 0
    ;;
  mcp__claude_ai_Atlasian__search|mcp__claude_ai_Atlasian__searchConfluenceUsingCql|mcp__claude_ai_Atlasian__searchJiraIssuesUsingJql|mcp__claude_ai_Atlasian__getConfluencePage|mcp__claude_ai_Atlasian__getConfluenceSpaces|mcp__claude_ai_Atlasian__getPagesInConfluenceSpace|mcp__claude_ai_Atlasian__getJiraIssue|mcp__claude_ai_Atlasian__getVisibleJiraProjects|mcp__claude_ai_Atlasian__getJiraProjectIssueTypesMetadata|mcp__claude_ai_Atlasian__atlassianUserInfo|mcp__claude_ai_Atlasian__getAccessibleAtlassianResources|mcp__claude_ai_Atlasian__getTransitionsForJiraIssue|mcp__claude_ai_Atlasian__jiraRead)
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Read-only Atlassian (claude_ai) MCP auto-approved"}}}'
    exit 0
    ;;
  # Gmail and Calendar MCP removed -- use `gws` CLI instead
esac

# No decision -- fall through to normal permission prompt
exit 0
