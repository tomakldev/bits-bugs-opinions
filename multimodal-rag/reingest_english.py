"""Re-ingest English File PDFs with per-page chunking.

Hybrid approach: embed PDF bytes (vector search) + Gemini transcription (content for LLM).
"""

import os
import sys
import time
import fitz  # PyMuPDF

from ingest import embed_pdf_bytes, embed_text, gemini
from db import insert_document, get_conn
from google.genai import types
from config import LLM_MODEL

ENGLISH_DIR = "/mnt/nas/claude/english"
PDFS = [
    "SB_part1_p1-85.pdf",
    "SB_part2_p86-170.pdf",
    "English_File_4th_edition_Upper_Intermediate_WB.pdf",
]

CLEANUP_EXTRA = [
    "English_File_4th_edition_Upper_Intermediate_Student's_Book.pdf",
]

SB_PART2_OFFSET = 85

DESCRIBE_PROMPT = (
    "Transcribe ALL text on this textbook page exactly as written. "
    "Include exercise labels (a, b, c...), instructions, sentences, blanks (as ___), "
    "vocabulary, grammar rules, reading passages, headers, and page/unit numbers. "
    "Keep exercise labels preserved. Be complete and accurate."
)

MAX_RETRIES = 2


def describe_page(page_bytes: bytes) -> str:
    """Transcribe a single textbook page via Gemini. Retries on None."""
    for attempt in range(MAX_RETRIES + 1):
        try:
            response = gemini.models.generate_content(
                model=LLM_MODEL,
                contents=types.Content(parts=[
                    types.Part.from_bytes(data=page_bytes, mime_type="application/pdf"),
                    types.Part.from_text(text=DESCRIBE_PROMPT),
                ]),
            )
            if response.text:
                return response.text
        except Exception:
            pass
        if attempt < MAX_RETRIES:
            time.sleep(2)
    return ""


def delete_old_chunks(pdf_filename: str):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM documents WHERE source_file LIKE %s OR source_file LIKE %s",
                (f"{pdf_filename}%", f"{pdf_filename}:%"),
            )
            deleted = cur.rowcount
        conn.commit()
    return deleted


def book_page(filename: str, page_idx: int) -> int:
    if "part2" in filename:
        return page_idx + 1 + SB_PART2_OFFSET
    return page_idx + 1


def reingest_pdf(filepath: str, dry_run: bool = False):
    filename = os.path.basename(filepath)
    doc = fitz.open(filepath)
    total_pages = len(doc)
    print(f"\n{'='*60}")
    print(f"PDF: {filename} ({total_pages} pages)")
    print(f"{'='*60}")

    if not dry_run:
        deleted = delete_old_chunks(filename)
        print(f"  Deleted {deleted} old chunks")

    ok = 0
    fail = 0

    for page_idx in range(total_pages):
        bp = book_page(filename, page_idx)
        chunk_name = f"{filename}:p{bp}"
        print(f"  Page {bp} ({page_idx+1}/{total_pages})...", end=" ", flush=True)

        if dry_run:
            print("[DRY RUN]")
            ok += 1
            continue

        try:
            chunk_doc = fitz.open()
            chunk_doc.insert_pdf(doc, from_page=page_idx, to_page=page_idx)
            chunk_bytes = chunk_doc.tobytes()
            chunk_doc.close()

            # Transcribe page content via Gemini vision
            description = describe_page(chunk_bytes)
            book_type = "WB" if "WB" in filename else "SB"
            if description:
                content = f"English File Upper-Intermediate {book_type} page {bp}\n\n{description}"
            else:
                content = f"English File Upper-Intermediate {book_type} page {bp}"

            # Embed the transcription TEXT (not PDF bytes) so text queries match
            vector = embed_text(content)

            insert_document(
                content=content,
                embedding=vector,
                source_type="pdf",
                source_file=chunk_name,
                chunk_index=page_idx,
                metadata={
                    "source_pdf": filename,
                    "page": bp,
                    "book": book_type,
                },
            )
            ok += 1
            desc_len = len(description) if description else 0
            print(f"OK ({desc_len} chars)")

        except Exception as e:
            fail += 1
            print(f"FAIL: {e}")
            time.sleep(5)

    doc.close()
    print(f"\n  Done: {ok} OK, {fail} failed out of {total_pages} pages")
    return ok, fail


def main():
    dry_run = "--dry-run" in sys.argv
    only = None
    for arg in sys.argv[1:]:
        if arg.startswith("--only="):
            only = arg.split("=", 1)[1]

    total_ok = 0
    total_fail = 0

    if not dry_run and not only:
        for extra in CLEANUP_EXTRA:
            deleted = delete_old_chunks(extra)
            if deleted:
                print(f"Cleaned up {deleted} old chunks from {extra}")

    for pdf_name in PDFS:
        if only and only not in pdf_name:
            continue
        filepath = os.path.join(ENGLISH_DIR, pdf_name)
        if not os.path.exists(filepath):
            print(f"SKIP (not found): {filepath}")
            continue
        ok, fail = reingest_pdf(filepath, dry_run=dry_run)
        total_ok += ok
        total_fail += fail

    print(f"\n{'='*60}")
    print(f"TOTAL: {total_ok} pages ingested, {total_fail} failed")
    if dry_run:
        print("(DRY RUN - no changes made)")


if __name__ == "__main__":
    main()
