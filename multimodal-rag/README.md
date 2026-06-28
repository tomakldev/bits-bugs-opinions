# Multimodal RAG — persistent memory system for AI agents

A production RAG system built to give AI agents persistent memory across sessions. 
Running daily as the single source of truth across multiple projects and client environments.

## Architecture

- **pgvector** (PostgreSQL) as the vector store
- **Gemini Embedding 2** (3072-dim) for embeddings
- **SQLite** knowledge graph for structured entity/relationship facts
- **MCP server** exposing the knowledge base to Claude Code agents as typed tools
- **File watcher** for auto-ingest of documents dropped in a watch folder
- **Docker Compose** for the full stack (pgvector, app, mcp, watcher)

## Key components

| File | Purpose |
|---|---|
| `mcp_server.py` | MCP server — exposes RAG search, KG query, diary write to AI agents |
| `knowledge_graph.py` | SQLite KG — stores entity facts, relationships, and timelines |
| `ingest.py` | Document ingestion with chunking and metadata enforcement |
| `watcher.py` | File watcher — auto-ingests files dropped in `/nas/RAG/` |
| `diary.py` | Session diary — writes structured entries to pgvector at session end |
| `db.py` | pgvector connection and embedding storage |
| `query.py` | Semantic search over the vector store |
| `batch_ingest.py` | Bulk ingest for migrating existing document libraries |

## Setup

Copy `.env.example` to `.env` and fill in your values:

```
GEMINI_API_KEY=
PROJECT=your-gcp-project
LOCATION=europe-west4
DB_HOST=127.0.0.1
DB_PORT=5433
DB_NAME=ragdb
DB_USER=raguser
DB_PASSWORD=
```

Then:

```bash
docker compose up -d
python ingest.py path/to/document.pdf
```

## Blog post

Full write-up: [Building a local RAG system as persistent memory for Claude Code](https://tomakl.dev)
