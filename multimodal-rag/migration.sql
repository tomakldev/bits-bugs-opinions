CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;

CREATE TABLE documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content TEXT,
  embedding VECTOR(3072),
  source_type TEXT NOT NULL,
  source_file TEXT,
  chunk_index INT,
  metadata JSONB DEFAULT '{}',
  event_date DATE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- No vector index needed at <1000 docs; sequential scan is fast enough.
-- pgvector HNSW/IVFFlat indexes are limited to 2000 dims.

CREATE OR REPLACE FUNCTION match_documents(
  query_embedding VECTOR(3072),
  match_count INT DEFAULT 5,
  filter_source_type TEXT DEFAULT NULL
) RETURNS TABLE(
  id UUID,
  content TEXT,
  source_type TEXT,
  source_file TEXT,
  chunk_index INT,
  metadata JSONB,
  similarity FLOAT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    d.id, d.content, d.source_type, d.source_file,
    d.chunk_index, d.metadata,
    1 - (d.embedding <=> query_embedding) AS similarity
  FROM documents d
  WHERE (filter_source_type IS NULL OR d.source_type = filter_source_type)
  ORDER BY d.embedding <=> query_embedding
  LIMIT match_count;
END;
$$ LANGUAGE plpgsql;
