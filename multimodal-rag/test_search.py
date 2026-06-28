from query import query_rag
import sys

def test_search(q):
    print(f"Query: {q}")
    results = query_rag(q, top_k=3)
    for r in results:
        score = r.get("similarity", 0)
        rs = r.get("rerank_score", 0)
        print(f"\n[{r.get('source_file')}] (Sim: {score:.3f}, Rerank: {rs:.1f})")
        print("-" * 40)
        print(r.get("content")[:500] + "...")
        print("=" * 60)

if __name__ == "__main__":
    query = sys.argv[1] if len(sys.argv) > 1 else "what i have to remember"
    test_search(query)
