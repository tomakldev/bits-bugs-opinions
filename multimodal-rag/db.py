"""Database helpers for local pgvector with parent-child support."""

import json
import psycopg2
from psycopg2.extras import RealDictCursor
from config import DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD

def get_conn():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
        user=DB_USER, password=DB_PASSWORD,
    )

def clear_source_data(source_file: str):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM parent_documents WHERE source_file = %s", (source_file,))
        conn.commit()

def insert_parent_document(content, source_type, source_file, metadata=None, event_date=None):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO parent_documents (content, source_type, source_file, metadata, event_date)
                   VALUES (%s, %s, %s, %s, %s) RETURNING id""",
                (content, source_type, source_file, json.dumps(metadata or {}), event_date)
            )
            return cur.fetchone()[0]

def insert_child_document(parent_id, content, embedding, chunk_index=None):
    vec_str = "[" + ",".join(str(v) for v in embedding) + "]"
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO child_documents (parent_id, content, embedding, chunk_index)
                   VALUES (%s, %s, %s::vector, %s)""",
                (parent_id, content, vec_str, chunk_index)
            )
        conn.commit()

def match_documents(query_embedding: list[float], match_count: int = 5, filter_source_type: str = None) -> list[dict]:
    vec_str = "[" + ",".join(str(v) for v in query_embedding) + "]"
    with get_conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # Simple vector search joining parent and child
            cur.execute(
                """SELECT p.content, p.source_type, p.source_file, p.metadata, p.event_date,
                          1 - (c.embedding <=> %s::vector) AS similarity
                   FROM child_documents c
                   JOIN parent_documents p ON c.parent_id = p.id
                   WHERE (%s IS NULL OR p.source_type = %s)
                   ORDER BY c.embedding <=> %s::vector
                   LIMIT %s""",
                (vec_str, filter_source_type, filter_source_type, vec_str, match_count)
            )
            return cur.fetchall()
