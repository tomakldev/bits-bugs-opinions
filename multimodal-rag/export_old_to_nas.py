"""Export documents from ragdb_old (restored backup) to /mnt/nas/RAG/ as .md files.

Each file includes YAML frontmatter preserving original metadata so the
source_type can be reconstructed later if needed.
"""

import os
import re
import json
import psycopg2

OUT_DIR = os.environ.get("OUT_DIR", "/mnt/nas/RAG/recovered-from-backup")
DB_HOST = os.environ.get("DB_HOST", "pgvector")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = "ragdb_old"
DB_USER = "raguser"
DB_PASSWORD = os.environ["DB_PASSWORD"]


def safe_filename(name: str) -> str:
    """Make a filename safe for cross-platform filesystems."""
    name = re.sub(r"[^\w\-. ]", "_", name)
    name = name.strip().strip(".")
    return name[:180] or "untitled"


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    conn = psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
        user=DB_USER, password=DB_PASSWORD,
    )
    cur = conn.cursor()
    cur.execute("""
        SELECT id, source_file, source_type, content, metadata, event_date, created_at
        FROM documents
        ORDER BY created_at
    """)
    rows = cur.fetchall()
    print(f"Fetched {len(rows)} documents from {DB_NAME}")

    written = 0
    skipped = 0
    for doc_id, source_file, source_type, content, metadata, event_date, created_at in rows:
        if not content or not content.strip():
            print(f"  SKIP empty: {source_file}")
            skipped += 1
            continue

        base = safe_filename(source_file or f"doc-{doc_id}")
        if not base.endswith(".md"):
            base = f"{base}.md"

        prefix = f"{source_type}_"
        if not base.startswith(prefix):
            base = prefix + base

        out_path = os.path.join(OUT_DIR, base)

        if os.path.exists(out_path):
            out_path = os.path.join(OUT_DIR, f"{doc_id.hex[:8]}_{base}")

        fm_lines = [
            "---",
            f"source_type: {source_type}",
            f"source_file: {source_file}",
            f"event_date: {event_date.isoformat() if event_date else ''}",
            f"created_at: {created_at.isoformat() if created_at else ''}",
            f"original_id: {doc_id}",
            f"metadata: {json.dumps(metadata or {}, ensure_ascii=False)}",
            "---",
            "",
        ]

        with open(out_path, "w", encoding="utf-8") as f:
            f.write("\n".join(fm_lines))
            f.write("\n")
            f.write(content.strip())
            f.write("\n")

        written += 1

    cur.close()
    conn.close()
    print(f"\nWritten: {written}  Skipped: {skipped}  Dir: {OUT_DIR}")


if __name__ == "__main__":
    main()
