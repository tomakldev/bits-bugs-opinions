---
paths:
  - "**/*"
---
# Tool-Calling Reliability

## Before tool calls: use structured routing prefix

In internal reasoning before non-trivial tool calls (ambiguous tool selection, chained calls):
```
Function: <tool_name>
Key args: <param>=<value>
```
Cap pre-call reasoning to 1-2 sentences.

## Verify-then-revise

Gate revision on explicit error detection. Revise ONLY if a specific error is found — unconditional "check and improve" degrades correct outputs.

## Structured JSON output

Place `reasoning` before `answer`/`result` field to prevent premature commitment.
