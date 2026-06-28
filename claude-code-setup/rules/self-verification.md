# Self-verification (Chain-of-Verification)

After producing a solution, plan, or action sequence, verify it before executing. This applies to:

- Destructive operations (git push, file deletion, database changes)
- Production changes (deploy, Azure/AWS ops, Vault secret rotation)
- Multi-step plans with 3+ steps
- Code changes affecting more than 3 files

## Verification steps

1. Re-read the original user request. Does the proposed action match what was asked?
2. For each critical step, ask: "What assumption am I making here? Is it confirmed or guessed?"
3. Check for unintended side effects: "What else could this change break?"
4. If the action is irreversible, state the rollback plan before proceeding.

## Failure taxonomy (check before finalizing)

Before completing any plan or code change, scan for:

1. **Scope creep** -- did the solution touch more than the user asked? Trim to minimum required.
2. **Assumed context** -- did the solution rely on facts not confirmed by tool calls or user statements? Flag any guess as a guess.
3. **Missing edge case** -- for code: null/empty input, concurrent access, network failure. For ops: partial failure, rollback path.
4. **Silent breakage** -- does the change break an interface, config key, or contract that other code depends on but isn't visible in the immediate context?
5. **Output format drift** -- for agents producing structured output (JSON, tickets, Confluence): does the output match the expected schema, not just the content?

## Semi-formal reasoning for code and fault analysis

For code review, bug analysis, and patch equivalence checks, structure reasoning explicitly:

1. **Premises** -- known facts from reading the code (variable values, invariants, API contracts)
2. **Trace** -- step through the execution path for the case under review
3. **Conclusion** -- verdict with explicit reference to the premises and trace

Do not skip to the conclusion. A conclusion unsupported by a visible trace is a guess. This structure improves patch equivalence accuracy from ~78% to ~93% (arXiv 2603.01896).

## When to skip

- Simple reads, searches, or informational queries
- Single-file edits with clear intent
- Operations already gated by user confirmation (e.g., AskUserQuestion)

## For agents

Agents running with `cot` strategy should add a verification pass after their reasoning chain. The enterprise-app-specialist and deploy-verifier agents should always verify before recommending destructive actions on production systems.
