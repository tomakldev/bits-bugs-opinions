#!/usr/bin/env bash
# permission-auto-approve.sh (simplified)
# Auto-approve safe operations, deny destructive ones, prompt for the rest.

case "$TOOL" in
  Read|Glob|Grep) echo '{"decision":"approve"}' ;;
  Bash)
    case "$COMMAND" in
      *"rm -rf /"*) echo '{"decision":"deny"}' ;;
      *"git push --force"*) echo '{"decision":"deny"}' ;;
      *"git reset --hard"*) echo '{"decision":"deny"}' ;;
      # ... more patterns
    esac ;;
esac
