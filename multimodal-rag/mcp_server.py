"""Lightweight MCP server for RAG: search, save, delete, knowledge graph, diary."""

import json
from mcp.server.fastmcp import FastMCP
from mcp.types import TextContent
from query import query_rag
from ingest import embed_text
from db import get_conn, insert_parent_document, insert_child_document
import knowledge_graph as kg
from diary import diary_write as _diary_write, diary_read as _diary_read

mcp = FastMCP("rag", host="0.0.0.0", port=7861)

MAX_RESULT_CHARS = 50_000
RAG_SNIPPET_CHARS = 500


def _large_text(text: str) -> list[TextContent]:
    """Return list of TextContent with anthropic/maxResultSizeChars for large results."""
    return [TextContent(type="text", text=text, _meta={"anthropic/maxResultSizeChars": MAX_RESULT_CHARS})]


# ── RAG tools ────────────────────────────────────────────────────────────────

@mcp.tool()
def rag_search(question: str, top_k: int = 5, full: bool = False) -> list[TextContent]:
    """Search the knowledge base for documents matching your question. Returns matched documents with content and similarity scores for Claude to interpret.

    Args:
        question: Natural language question to search for.
        top_k: Number of results to return (default 5).
        full: If True, return full document content. If False (default), truncate to ~500 chars per doc to save tokens.
    """
    matches = query_rag(question, top_k=top_k)
    if not matches:
        return "No relevant documents found."
    parts = []
    for m in matches:
        date_str = f", date: {m['event_date']}" if m.get("event_date") else ""
        label = f"[{m['source_type']}] {m['source_file']} (similarity: {m['similarity']:.3f}{date_str})"
        content = m['content'] if full else m['content'][:RAG_SNIPPET_CHARS] + ("..." if len(m['content']) > RAG_SNIPPET_CHARS else "")
        parts.append(f"{label}\n{content}")
    return _large_text("\n\n---\n\n".join(parts))


@mcp.tool()
def rag_save(
    title: str,
    content: str,
    tags: str = "",
    source_type: str = "text",
    event_date: str = "",
) -> str:
    """Save a document directly to the RAG knowledge base. Embeds and stores in pgvector.

    Args:
        title: Document title, used as source_file identifier.
        content: Full text content to embed and store.
        tags: Comma-separated tags for metadata (e.g. 'lapa,azure,security').
        source_type: Type of content: text, runbook, ticket, email, guide, report, decision.
        event_date: When the event happened (YYYY-MM-DD). Optional, separate from storage date.
    """
    title = title.strip()
    content = content.strip()
    event_date = event_date.strip() if event_date else ""

    if not title or not content:
        return "Error: title and content are required."

    slug = title.lower().replace(" ", "-")
    for ch in ",:;!?'\"()[]{}/@#$%^&*~`":
        slug = slug.replace(ch, "")
    source_file = f"{slug}.md"

    tag_list = [t.strip() for t in tags.split(",") if t.strip()] if tags else []
    metadata = {"title": title, "tags": tag_list, "source_type": source_type}

    try:
        # embed_text now internally uses standard API key
        vector = embed_text(content)
        # Create parent then child for local pgvector
        pid = insert_parent_document(
            content=content,
            source_type=source_type,
            source_file=source_file,
            metadata=metadata,
            event_date=event_date or None,
        )
        insert_child_document(parent_id=pid, content=content, embedding=vector)
    except Exception as e:
        return f"Error saving {source_file}: {type(e).__name__}: {e}"

    return f"Saved: {source_file} ({len(vector)} dims, {len(content)} chars, tags: {tag_list})"


@mcp.tool()
def rag_delete(source_file: str) -> str:
    """Delete documents from the RAG knowledge base by source_file name. Uses exact match.

    Args:
        source_file: The source_file identifier to delete (e.g. 'lapa-migration-guide.md').
    """
    if not source_file.strip():
        return "Error: source_file is required."
    name = source_file.strip()
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "DELETE FROM parent_documents WHERE source_file = %s RETURNING id, source_file",
                    (name,),
                )
                rows = cur.fetchall()
            conn.commit()
    except Exception as e:
        return f"Error deleting: {type(e).__name__}"
    if not rows:
        return f"No documents found with source_file = '{name}'"
    return f"Deleted {len(rows)} document(s) with source_file = '{name}'"


# ── Knowledge Graph tools ────────────────────────────────────────────────────

@mcp.tool()
def kg_query(entity: str, direction: str = "both", as_of: str = "", limit: int = 30, include_expired: bool = False) -> str | list[TextContent]:
    """Query the knowledge graph for an entity's relationships."""
    result = kg.query_entity(entity, direction=direction, as_of=as_of or None)
    if not result["entity"]:
        return f"Entity '{entity}' not found in knowledge graph."
    triples = result["triples"]
    if not include_expired:
        triples = [t for t in triples if t["valid_to"] is None]
    total = len(triples)
    if limit > 0:
        triples = triples[:limit]
    lines = [f"Entity: {result['entity']['name']} (type: {result['entity']['type']}, {total} active triples)"]
    for t in triples:
        status = "active" if t["valid_to"] is None else f"expired {t['valid_to']}"
        lines.append(f"  [{t['id']}] {t['subject']} --{t['predicate']}--> {t['object']} ({status})")
    return _large_text("\n".join(lines))


@mcp.tool()
def kg_add(subject: str, predicate: str, object: str, valid_from: str = "", confidence: float = 1.0) -> str:
    """Add a fact (triple) to the knowledge graph."""
    normalized = kg.normalize_predicate(predicate)
    triple_id = kg.add_triple(subject, predicate, object, valid_from=valid_from or None, confidence=confidence)
    return f"Added triple [{triple_id}]: {subject} --{normalized}--> {object}"


@mcp.tool()
def kg_invalidate(triple_id: int, valid_to: str = "") -> str:
    """Mark a fact as no longer true by setting its expiry date."""
    kg.invalidate_triple(triple_id, valid_to=valid_to or None)
    return f"Triple [{triple_id}] marked as expired."


@mcp.tool()
def kg_timeline(entity: str = "", limit: int = 30, events_only: bool = False) -> str | list[TextContent]:
    """Show chronological timeline of facts, optionally filtered to one entity."""
    triples = kg.get_timeline(entity=entity or None)
    if not triples:
        return "No facts in knowledge graph."
    total = len(triples)
    if limit > 0 and total > limit:
        triples = triples[-limit:]
    lines = []
    for t in triples:
        date_str = t.get("valid_from") or t.get("created_at", "")[:10]
        status = "active" if t["valid_to"] is None else f"expired {t['valid_to']}"
        lines.append(f"[{date_str}] {t['subject']} --{t['predicate']}--> {t['object']} ({status})")
    return _large_text("\n".join(lines))


@mcp.tool()
def kg_stats() -> str:
    """Show knowledge graph statistics."""
    stats = kg.get_stats()
    return json.dumps(stats, indent=2)


@mcp.tool()
def kg_query_enriched(entity: str, top_k: int = 3) -> str | list[TextContent]:
    """Hybrid KG+RAG query."""
    result = kg.query_entity(entity, direction="both")
    entity_info = result["entity"]
    triples = [t for t in result["triples"] if t["valid_to"] is None]

    parts = []
    if entity_info:
        parts.append(f"## KG: {entity_info['name']} (type: {entity_info['type']})")
        for t in triples:
            parts.append(f"  {t['subject']} --{t['predicate']}--> {t['object']}")
    else:
        parts.append(f"## KG: '{entity}' not found.")

    parts.append(f"\n## RAG: top {top_k} related documents")
    matches = query_rag(entity, top_k=top_k)
    if matches:
        for m in matches:
            parts.append(f"  [{m['source_type']}] {m['source_file']} (sim: {m['similarity']:.3f})\n  {m['content'][:RAG_SNIPPET_CHARS]}...")
    else:
        parts.append("  No related documents found.")

    return _large_text("\n".join(parts))


# ── Diary tools ──────────────────────────────────────────────────────────────

@mcp.tool()
def diary_write_entry(agent_name: str, content: str, tags: str = "") -> str:
    """Write a diary entry."""
    tag_list = [t.strip() for t in tags.split(",") if t.strip()] if tags else []
    try:
        fname = _diary_write(agent_name, content, tag_list)
        return f"Diary entry saved: {fname}"
    except Exception as e:
        return f"Error: {type(e).__name__}: {e}"


@mcp.tool()
def diary_read_recent(n: int = 5) -> str | list[TextContent]:
    """Read recent diary entries."""
    entries = _diary_read(n)
    if not entries:
        return "No diary entries found."
    parts = []
    for e in entries:
        parts.append(f"[{str(e.get('created_at', ''))}]\n{e['content']}")
    return _large_text("\n\n---\n\n".join(parts))


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
