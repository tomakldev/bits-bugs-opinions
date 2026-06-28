"""Structured per-session diary entries stored in pgvector with parent-child support."""

from datetime import datetime
from ingest import embed_text
from db import get_conn, insert_parent_document, insert_child_document
from psycopg2.extras import RealDictCursor

def diary_write(agent_name, content, tags=None):
    """Save a diary entry to RAG."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    date_slug = datetime.now().strftime("%Y%m%d-%H%M")
    source_file = f"diary-{agent_name}-{date_slug}.md"

    full_content = f"# Diary: {agent_name} ({timestamp})\n\n{content}"
    metadata = {
        "type": "diary",
        "agent_name": agent_name,
        "timestamp": timestamp,
        "tags": tags or [],
    }

    # 1. Generate embedding
    vector = embed_text(full_content)

    # 2. Insert parent
    pid = insert_parent_document(
        content=full_content,
        source_type="diary",
        source_file=source_file,
        metadata=metadata
    )

    # 3. Insert child (for search)
    insert_child_document(parent_id=pid, content=full_content, embedding=vector)

    return source_file

def diary_read(n=5):
    """Return the N most recent diary entries."""
    with get_conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """SELECT content, metadata, created_at FROM parent_documents
                   WHERE source_type = 'diary'
                   ORDER BY created_at DESC LIMIT %s""",
                (n,),
            )
            return cur.fetchall()
