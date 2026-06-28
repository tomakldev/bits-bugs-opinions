#!/usr/bin/env python3
"""Delete a document from RAG by ID."""
import sys
from db import get_conn

if len(sys.argv) < 2:
    print("Usage: rag_delete.py <doc_id> [doc_id2 ...]", file=sys.stderr)
    sys.exit(1)

try:
    with get_conn() as conn:
        with conn.cursor() as cur:
            for doc_id in sys.argv[1:]:
                cur.execute("DELETE FROM documents WHERE id = %s RETURNING source_file", (doc_id,))
                row = cur.fetchone()
                if row:
                    print(f"Deleted: {row[0]} ({doc_id})")
                else:
                    print(f"Not found: {doc_id}")
        conn.commit()
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
