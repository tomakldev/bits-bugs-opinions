"""Save a session summary to RAG for long-term memory recall."""

import sys
import os
from datetime import datetime

from ingest import embed_text
from db import insert_document


def save_session(summary: str, tags: str = ""):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    filename = f"session-{datetime.now().strftime('%Y%m%d-%H%M')}.md"

    content = f"# Session Summary ({timestamp})\n\n"
    if tags:
        content += f"Tags: {tags}\n\n"
    content += summary

    vector = embed_text(content)
    insert_document(
        content=content,
        embedding=vector,
        source_type="text",
        source_file=filename,
        metadata={"type": "session", "timestamp": timestamp, "tags": tags},
    )
    print(f"Saved session summary as {filename}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python save_session.py 'summary text' [tags]")
        sys.exit(1)
    summary = sys.argv[1]
    tags = sys.argv[2] if len(sys.argv) > 2 else ""
    save_session(summary, tags)
