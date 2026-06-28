"""Batch ingest: scan a directory tree and ingest all supported files."""

import os
import sys
import argparse
import glob

from ingest import embed_text, embed_image, embed_video, embed_pdf_bytes, describe_content, describe_content_bytes
from db import insert_document
from video_chunker import chunk_video

SUPPORTED = {
    "text": (".md", ".txt"),
    "pdf": (".pdf",),
    "image": (".png", ".jpg", ".jpeg"),
    "video": (".mp4",),
}


def find_files(directory: str, exclude: list[str] | None = None) -> list[tuple[str, str]]:
    """Walk directory and return (path, type) tuples for supported files."""
    exclude = [e.rstrip("/") for e in (exclude or [])]
    results = []
    for root, dirs, files in os.walk(directory):
        if exclude:
            dirs[:] = [d for d in dirs if not any(e in os.path.join(root, d) for e in exclude)]
        for f in files:
            ext = os.path.splitext(f)[1].lower()
            for ftype, exts in SUPPORTED.items():
                if ext in exts:
                    results.append((os.path.join(root, f), ftype))
                    break
    return sorted(results)


def ingest_one(filepath: str, ftype: str, dry_run: bool = False) -> bool:
    """Ingest a single file. Returns True on success."""
    filename = os.path.basename(filepath)

    if dry_run:
        print(f"  [DRY RUN] Would ingest {ftype}: {filepath}")
        return True

    try:
        if ftype == "text":
            with open(filepath, "r", encoding="utf-8") as f:
                text = f.read()
            if not text.strip():
                print(f"  Skipping empty file: {filename}")
                return False
            vector = embed_text(text)
            insert_document(
                content=text,
                embedding=vector,
                source_type="text",
                source_file=filename,
                metadata={"source_path": filepath},
            )

        elif ftype == "pdf":
            import fitz  # PyMuPDF

            doc = fitz.open(filepath)
            total_pages = len(doc)
            PAGES_PER_CHUNK = 6  # Gemini Embedding 2 limit: max 6 pages per PDF

            for chunk_idx in range(0, total_pages, PAGES_PER_CHUNK):
                end_page = min(chunk_idx + PAGES_PER_CHUNK, total_pages)
                chunk_name = f"{filename}:p{chunk_idx+1}-{end_page}"
                print(f"    Chunk {chunk_idx//PAGES_PER_CHUNK + 1}: pages {chunk_idx+1}-{end_page}")

                chunk_doc = fitz.open()
                chunk_doc.insert_pdf(doc, from_page=chunk_idx, to_page=end_page - 1)
                chunk_bytes = chunk_doc.tobytes()
                chunk_doc.close()

                description = describe_content_bytes(chunk_bytes, "application/pdf")
                vector = embed_pdf_bytes(chunk_bytes)
                insert_document(
                    content=description,
                    embedding=vector,
                    source_type="pdf",
                    source_file=chunk_name,
                    chunk_index=chunk_idx // PAGES_PER_CHUNK,
                    metadata={"source_path": filepath, "source_pdf": filename,
                              "pages": f"{chunk_idx+1}-{end_page}"},
                )

            doc.close()

        elif ftype == "image":
            mime = "image/png" if filepath.endswith(".png") else "image/jpeg"
            description = describe_content(filepath, mime)
            vector = embed_image(filepath)
            insert_document(
                content=description,
                embedding=vector,
                source_type="image",
                source_file=filename,
                metadata={"description": description, "source_path": filepath},
            )

        elif ftype == "video":
            import tempfile
            import shutil

            chunk_dir = tempfile.mkdtemp(prefix="rag_batch_")
            chunk_paths = chunk_video(filepath, output_dir=chunk_dir)

            for i, cpath in enumerate(chunk_paths):
                chunk_name = os.path.basename(cpath)
                print(f"    Chunk {i+1}/{len(chunk_paths)}: {chunk_name}")
                description = describe_content(cpath, "video/mp4")
                vector = embed_video(cpath)
                insert_document(
                    content=description,
                    embedding=vector,
                    source_type="video",
                    source_file=chunk_name,
                    chunk_index=i,
                    metadata={
                        "description": description,
                        "chunk_index": i,
                        "source_video": filename,
                        "source_path": filepath,
                    },
                )

            shutil.rmtree(chunk_dir, ignore_errors=True)

        print(f"  OK: {filename}")
        return True

    except Exception as e:
        print(f"  FAIL: {filename} -- {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="Batch ingest files into multimodal RAG")
    parser.add_argument("directory", help="Directory to scan recursively")
    parser.add_argument("--dry-run", action="store_true", help="List files without ingesting")
    parser.add_argument("--limit", type=int, default=0, help="Max files to ingest (0=unlimited)")
    parser.add_argument("--exclude", nargs="*", default=[], help="Directory names to exclude")
    parser.add_argument("--exclude-ext", nargs="*", default=[], help="File extensions to exclude (e.g. .png)")
    args = parser.parse_args()

    if not os.path.isdir(args.directory):
        print(f"Error: {args.directory} is not a directory")
        sys.exit(1)

    files = find_files(args.directory, exclude=args.exclude)
    if args.exclude_ext:
        skip = {e if e.startswith(".") else f".{e}" for e in args.exclude_ext}
        files = [(p, t) for p, t in files if os.path.splitext(p)[1].lower() not in skip]
    print(f"Found {len(files)} supported files in {args.directory}")

    if args.limit > 0:
        files = files[:args.limit]
        print(f"Limited to {args.limit} files")

    counts = {"text": 0, "pdf": 0, "image": 0, "video": 0}
    ok = 0
    fail = 0

    for filepath, ftype in files:
        print(f"[{ftype.upper()}] {filepath}")
        if ingest_one(filepath, ftype, dry_run=args.dry_run):
            ok += 1
            counts[ftype] += 1
        else:
            fail += 1

    print(f"\nDone: {ok} ingested, {fail} failed")
    print(f"  Text: {counts['text']}, PDF: {counts['pdf']}, Images: {counts['image']}, Video: {counts['video']}")


if __name__ == "__main__":
    main()
