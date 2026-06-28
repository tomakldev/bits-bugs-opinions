---
paths:
  - "**/*.sh"
---
# Bash Script Rules

- Always start with `#!/usr/bin/env bash` and `set -euo pipefail`
- Quote all variables: `"$VAR"` not `$VAR`
- Use `[[ ]]` over `[ ]` for conditionals
- Use absolute paths in scripts
- Use `$(command)` not backticks for command substitution
- Check command existence with `command -v` before using
- Use `local` for function variables
- Use `readonly` for constants
- Trap errors: `trap 'cleanup' EXIT ERR`
- Use `mktemp` for temp files, clean up on exit
