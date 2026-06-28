"""Direct migration from ragdb_old.documents to ragdb.parent_documents + child_documents.

Reuses existing embeddings (same VECTOR(3072) dimension in both schemas).
Preserves source_type, source_file, event_date, metadata.
"""

import os
import json
import psycopg2

DB_HOST = os.environ.get("DB_HOST", "pgvector")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_USER = os.environ.get("DB_USER", "raguser")
DB_PASSWORD = os.environ["DB_PASSWORD"]


def main():
    src = psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname="ragdb_old",
                           user=DB_USER, password=DB_PASSWORD)
    dst = psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname="ragdb",
                           user=DB_USER, password=DB_PASSWORD)

    src_cur = src.cursor()
    dst_cur = dst.cursor()

    src_cur.execute("""
        SELECT id, content, source_type, source_file, chunk_index,
               metadata, event_date, embedding::text
        FROM documents
        ORDER BY created_at
    """)
    rows = src_cur.fetchall()
    print(f"Source: {len(rows)} documents in ragdb_old")

    dst_cur.execute("SELECT source_file FROM parent_documents")
    existing = {r[0] for r in dst_cur.fetchall()}
    print(f"Destination: {len(existing)} source_files already present in ragdb")

    migrated = 0
    skipped_dupe = 0
    skipped_empty = 0

    for (doc_id, content, source_type, source_file, chunk_index,
         metadata, event_date, embedding_text) in rows:

        if not content or not content.strip():
            skipped_empty += 1
            continue

        if source_file in existing:
            skipped_dupe += 1
            continue

        meta = metadata if isinstance(metadata, dict) else (json.loads(metadata) if metadata else {})
        meta["migrated_from"] = "ragdb_old"
        meta["original_id"] = str(doc_id)
        if chunk_index is not None:
            meta["original_chunk_index"] = chunk_index

        dst_cur.execute(
            """
            INSERT INTO parent_documents (content, source_type, source_file, metadata, event_date)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id
            """,
            (content, source_type, source_file, json.dumps(meta), event_date),
        )
        parent_id = dst_cur.fetchone()[0]

        dst_cur.execute(
            """
            INSERT INTO child_documents (parent_id, content, embedding, chunk_index)
            VALUES (%s, %s, %s::vector, 0)
            """,
            (parent_id, content, embedding_text),
        )

        migrated += 1
        if migrated % 25 == 0:
            dst.commit()
            print(f"  committed {migrated} / {len(rows)}")

    dst.commit()
    print(f"\nMigrated: {migrated}  Skipped duplicate: {skipped_dupe}  Skipped empty: {skipped_empty}")

    dst_cur.execute("SELECT count(*) FROM parent_documents")
    print(f"ragdb parent_documents total: {dst_cur.fetchone()[0]}")
    dst_cur.execute("SELECT count(*) FROM child_documents")
    print(f"ragdb child_documents total: {dst_cur.fetchone()[0]}")
    dst_cur.execute("SELECT source_type, count(*) FROM parent_documents GROUP BY source_type ORDER BY 2 DESC")
    print("source_type distribution:")
    for stype, cnt in dst_cur.fetchall():
        print(f"  {stype}: {cnt}")

    src_cur.close(); dst_cur.close()
    src.close(); dst.close()


if __name__ == "__main__":
    main()
