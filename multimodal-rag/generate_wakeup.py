"""Generate wake-up context for Claude Code session start.

L0: Static identity file (~100 tokens)
L1: Recent diary entries and high-signal docs from RAG

Outputs to stdout for injection by session-context.sh hook.
"""

import os
import sys

IDENTITY_PATH = os.path.expanduser("~/.claude/identity.txt")


def load_identity():
    try:
        with open(IDENTITY_PATH) as f:
            return f.read().strip()
    except FileNotFoundError:
        return ""


def query_recent():
    """Pull recent diary entries and decisions from RAG."""
    from db import get_conn
    docs = []
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                # Recent diary entries
                cur.execute(
                    """SELECT content, source_type, metadata, event_date, created_at
                       FROM documents
                       WHERE source_type IN ('diary', 'decision')
                       ORDER BY created_at DESC LIMIT 3""",
                )
                cols = [d[0] for d in cur.description]
                docs = [dict(zip(cols, row)) for row in cur.fetchall()]
    except Exception:
        pass
    return docs


def format_wakeup(identity, docs):
    parts = []
    if identity:
        parts.append(f"IDENTITY:\n{identity}")

    if docs:
        lines = ["RECENT MEMORY:"]
        for d in docs:
            date = str(d.get("event_date") or d.get("created_at", ""))[:10]
            stype = d.get("source_type", "")
            snippet = d["content"][:200].replace("\n", " ")
            lines.append(f"- [{stype}] {date}: {snippet}")
        parts.append("\n".join(lines))

    return "\n\n".join(parts)


if __name__ == "__main__":
    identity = load_identity()
    try:
        docs = query_recent()
    except Exception:
        docs = []
    output = format_wakeup(identity, docs)
    if output:
        print(output)
