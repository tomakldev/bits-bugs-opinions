# RAG Knowledge Base

All docs live in pgvector. Save via `mcp__rag__rag_save`, query via `mcp__rag__rag_search`.

## Save

`mcp__rag__rag_save(title, content, tags="comma,separated", source_type, event_date="YYYY-MM-DD")`

Source types: text, runbook, ticket, email, guide, report, decision, diary, transcript.
Use `event_date` when content has a specific date. Convert relative dates to absolute.

## Query

`mcp__rag__rag_search(question="...", top_k=5)` -- fuzzy text recall.
`mcp__rag__kg_query(entity="LAPA")` -- structured facts (ports, hosts, dependencies).
`mcp__rag__kg_add(subject, predicate, object, valid_from)` -- record new facts.
`mcp__rag__diary_write_entry(agent_name="claude", content="...", tags="...")` -- session summaries.

## When to query

- Past incidents, runbooks, decisions, internal docs -> RAG search
- Entity lookups (systems, infra, people) -> KG query
- NOT for: general programming (training data/Context7), current events (Tavily), local code (Grep/Glob)

## KG conventions

- Entities: proper case ("LAPA", "SJK"). Predicates: snake_case (runs_on, managed_by, uses, depends_on).
- When facts change: invalidate old triple, add new one.

## RAG ingest

Files in `/mnt/nas/RAG/` are auto-ingested and deleted. All other NAS folders persist.
