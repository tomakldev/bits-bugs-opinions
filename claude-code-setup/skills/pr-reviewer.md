---
name: pr-reviewer
version: 1.0.0
description: |
  Review a GitHub pull request. Use when the user asks to review a PR, check a pull
  request, look at changes in a PR, or when a GitHub PR URL or number is mentioned
  in the context of code review. Also trigger when the user says "what do you think
  of this PR", "can you check #123", shares a github.com/*/pull/* URL, or asks about
  code quality of recent changes. Handles both small and large PRs with parallel
  exploration for complex changes.
allowed-tools: Read, Grep, Glob, Bash, Task, WebFetch
---

# PR reviewer

Review a GitHub pull request. Strategy: self-refine (initial review, second pass for missed issues).

## Input

Extract PR number from user message. Accept: `#123`, `123`, or full GitHub PR URL.

## Steps

1. Fetch PR details and diff:
   ```bash
   gh pr view <number> --json title,body,files,additions,deletions,commits,reviewDecision,baseRefName,headRefName
   gh pr diff <number> --stat
   ```

2. Categorize changed files:
   - Core implementation (new modules, business logic)
   - Integration points (modified existing code)
   - Tests (unit, integration, e2e)
   - Configuration (feature flags, env vars, build configs)
   - Incidental (formatting, imports, minor refactors)

3. For small PRs (< 10 files): read the full diff.
   For large PRs (10+ files): launch 2-4 parallel Explore agents per file group.

4. Cross-check: diff analyzed files against the full file list.

5. Analyze for: code quality, security (OWASP top 10), logic errors, edge cases, missing error handling, convention violations, test coverage gaps.

6. Present structured review:
   - Summary (product-level, not file list)
   - Architecture (data flow, integration points)
   - Risk Level: Low / Medium / High
   - Issues Found (numbered, with file:line references)
   - Suggestions (optional improvements)
   - Verdict: Approve / Request Changes / Needs Discussion
