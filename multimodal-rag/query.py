"""Query engine: embed question -> similarity search -> return matched documents."""

import time
from google import genai
from google.genai import types

from config import GEMINI_API_KEY, EMBEDDING_MODEL, EMBEDDING_DIM, GCP_PROJECT, GCP_LOCATION
from db import match_documents

# Client for embeddings (standard API)
client_api = genai.Client(api_key=GEMINI_API_KEY)

def _embed_query(question: str) -> list[float]:
    """Embed a query with retry on rate limit."""
    for attempt in range(3):
        try:
            result = client_api.models.embed_content(
                model=EMBEDDING_MODEL,
                contents=[question],
                config=types.EmbedContentConfig(
                    task_type="RETRIEVAL_QUERY",
                    output_dimensionality=EMBEDDING_DIM,
                ),
            )
            return result.embeddings[0].values
        except Exception as e:
            if "429" in str(e) and attempt < 2:
                time.sleep(5 * (attempt + 1))
                continue
            raise

def query_rag(
    question: str,
    top_k: int = 5,
    source_type: str | None = None,
) -> list[dict]:
    """Run a RAG query: embed -> search pgvector -> return matched documents."""
    query_vector = _embed_query(question)
    return match_documents(query_vector, match_count=top_k, filter_source_type=source_type)

if __name__ == "__main__":
    import sys
    q = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else "What is LAPA?"
    print(f"Query: {q}\n")
    matches = query_rag(q)
    for m in matches:
        print(f"[{m['source_type']}] {m['source_file']} ({m['similarity']:.3f})")
