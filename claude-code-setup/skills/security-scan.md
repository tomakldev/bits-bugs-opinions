---
name: security-scan
version: 1.0.0
description: |
  Security scan of the codebase. Use when the user asks to check for vulnerabilities,
  hardcoded secrets, exposed env files, npm audit issues, or file permission problems.
  Also trigger proactively before committing security-sensitive changes, when reviewing
  code that handles credentials or authentication, when the user says "is this safe",
  "check for secrets", "audit the code", or mentions OWASP, CVEs, or security review.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
disallowed-tools: ["Bash(sudo rm *)", "Bash(sudo chmod *)", "Bash(sudo chown *)", "Bash(curl * | bash)", "Bash(wget * | sh)"]
---

# Security scan

Run a comprehensive security scan of the codebase. Strategy: self-consistent (scan from multiple threat perspectives).

## Steps

1. **Secrets scan** -- find hardcoded credentials using Grep:
   - Pattern: `(password|secret|api_key|token|apikey|auth)\s*[:=]\s*["'][^\s]{8,}` across .ts, .sh, .json, .yml, .yaml, .env files
   - Skip node_modules and .git

2. **Exposed env files** -- Glob for `.env*` files, check each is in .gitignore

3. **npm audit** (if package.json exists):
   ```bash
   npm audit --json 2>/dev/null | jq '.vulnerabilities | length'
   ```

4. **File permissions** -- world-writable files:
   ```bash
   find /home/tomakl/projects -perm -o+w -not -path '*node_modules*' -not -path '*.git*' -type f 2>/dev/null
   ```

5. **Docker security** -- check for privileged containers:
   ```bash
   docker ps --format '{{.Names}}' | xargs -I {} docker inspect {} --format '{{.Name}} privileged={{.HostConfig.Privileged}}'
   ```

6. **Report findings** in a table:
   - Severity: Critical / High / Medium / Low
   - Finding description
   - File and line
   - Recommended fix
