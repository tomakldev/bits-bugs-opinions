"""Gradio web UI for the multimodal RAG system -- search + upload/ingest."""

import os
import shutil
import tempfile

import gradio as gr

from query import query_rag
from ingest import embed_text, embed_image, embed_video, embed_pdf_bytes, describe_content, describe_content_bytes
from db import insert_document
from video_chunker import chunk_video

ASSETS_VIDEO = os.path.join("assets", "video")
ASSETS_IMAGES = os.path.join("assets", "images")


# -- Search tab --

def rag_search(question: str, top_k: int = 5) -> str:
    """Search the knowledge base for documents matching your question. Returns matched documents with similarity scores."""
    matches = query_rag(question, top_k=int(top_k))
    if not matches:
        return "No relevant documents found."
    parts = []
    for m in matches:
        label = f"[{m['source_type']}] {m['source_file']} (similarity: {m['similarity']:.3f})"
        parts.append(f"{label}\n{m['content']}")
    return "\n\n---\n\n".join(parts)


def search(question: str, top_k: int, source_filter: str):
    if not question.strip():
        return "No question provided.", "", None, []

    filter_type = None if source_filter == "All" else source_filter.lower()
    matches = query_rag(question, top_k=int(top_k), source_type=filter_type)

    if not matches:
        return "No relevant documents found.", "", None, []

    answer_parts = []
    sources_md = ""
    top_video = None
    image_previews = []

    for m in matches:
        sim_pct = m["similarity"] * 100
        sources_md += f"### {m['source_file']}\n"
        sources_md += f"Type: {m['source_type']} | Similarity: {sim_pct:.1f}%"
        if m.get("chunk_index") is not None:
            sources_md += f" | Chunk: {m['chunk_index']}"
        sources_md += "\n\n"
        preview = m["content"][:300] + "..." if len(m["content"]) > 300 else m["content"]
        sources_md += f"{preview}\n\n---\n\n"
        answer_parts.append(f"[{m['source_type']}] {m['source_file']} ({sim_pct:.0f}%)")

        if m["source_type"] == "video" and top_video is None:
            path = os.path.join(ASSETS_VIDEO, m["source_file"])
            if os.path.exists(path):
                top_video = path

        if m["source_type"] == "image":
            path = os.path.join(ASSETS_IMAGES, m["source_file"])
            if os.path.exists(path):
                image_previews.append(path)

    answer_summary = f"Found {len(matches)} results:\n" + "\n".join(answer_parts)
    return answer_summary, sources_md, top_video, image_previews


# -- Upload / ingest tab --

def ingest_file(file) -> str:
    """Accept a single uploaded file, detect type, embed, and store."""
    if file is None:
        return "No file uploaded."

    filepath = file.name if hasattr(file, "name") else str(file)
    filename = os.path.basename(filepath)
    ext = os.path.splitext(filename)[1].lower()

    log_lines: list[str] = []

    def log(msg: str):
        log_lines.append(msg)

    try:
        # -- Text --
        if ext in (".md", ".txt"):
            log(f"Detected text file: {filename}")
            with open(filepath, "r", encoding="utf-8") as f:
                text = f.read()
            log("  Embedding text...")
            vector = embed_text(text)
            insert_document(
                content=text,
                embedding=vector,
                source_type="text",
                source_file=filename,
            )
            log(f"  Ingested ({len(vector)} dims)")

        # -- PDF --
        elif ext == ".pdf":
            import fitz

            log(f"Detected PDF: {filename}")
            doc = fitz.open(filepath)
            total_pages = len(doc)
            log(f"  {total_pages} pages")

            PAGES_PER_CHUNK = 6  # Gemini Embedding 2 limit: max 6 pages per PDF
            chunks_done = 0
            for chunk_idx in range(0, total_pages, PAGES_PER_CHUNK):
                end_page = min(chunk_idx + PAGES_PER_CHUNK, total_pages)
                page_range = f"{chunk_idx+1}-{end_page}"
                log(f"  Processing pages {page_range}...")

                chunk_doc = fitz.open()
                chunk_doc.insert_pdf(doc, from_page=chunk_idx, to_page=end_page - 1)
                chunk_bytes = chunk_doc.tobytes()
                chunk_doc.close()

                description = describe_content_bytes(chunk_bytes, "application/pdf")
                vector = embed_pdf_bytes(chunk_bytes)
                chunk_name = f"{filename}:p{page_range}"
                insert_document(
                    content=description,
                    embedding=vector,
                    source_type="pdf",
                    source_file=chunk_name,
                    chunk_index=chunk_idx // PAGES_PER_CHUNK,
                    metadata={"source_pdf": filename, "pages": page_range},
                )
                chunks_done += 1
            doc.close()
            log(f"  Ingested {chunks_done} chunks ({total_pages} pages)")

        # -- Image --
        elif ext in (".png", ".jpg", ".jpeg"):
            mime = "image/png" if ext == ".png" else "image/jpeg"
            log(f"Detected image: {filename}")

            os.makedirs(ASSETS_IMAGES, exist_ok=True)
            saved_path = os.path.join(ASSETS_IMAGES, filename)
            shutil.copy2(filepath, saved_path)
            log(f"  Saved to {saved_path}")

            log("  Generating description...")
            description = describe_content(filepath, mime)
            log("  Embedding image...")
            vector = embed_image(filepath)
            insert_document(
                content=description,
                embedding=vector,
                source_type="image",
                source_file=filename,
                metadata={"description": description},
            )
            log(f"  Ingested ({len(vector)} dims)")

        # -- Video --
        elif ext == ".mp4":
            log(f"Detected video: {filename}")

            chunk_dir = tempfile.mkdtemp(prefix="rag_chunks_")
            log("  Chunking video (97s segments, 15s overlap)...")
            chunk_paths = chunk_video(filepath, output_dir=chunk_dir)
            log(f"  Created {len(chunk_paths)} chunks")

            os.makedirs(ASSETS_VIDEO, exist_ok=True)

            for i, cpath in enumerate(chunk_paths):
                chunk_name = os.path.basename(cpath)
                log(f"  Processing chunk {i+1}/{len(chunk_paths)}: {chunk_name}")

                log("    Generating description...")
                description = describe_content(cpath, "video/mp4")
                log("    Embedding video chunk...")
                vector = embed_video(cpath)

                insert_document(
                    content=description,
                    embedding=vector,
                    source_type="video",
                    source_file=chunk_name,
                    chunk_index=i,
                    metadata={"description": description, "chunk_index": i,
                              "source_video": filename},
                )
                log(f"    Chunk {i+1} ingested ({len(vector)} dims)")

                shutil.copy2(cpath, os.path.join(ASSETS_VIDEO, chunk_name))

            shutil.rmtree(chunk_dir, ignore_errors=True)
            log(f"  All {len(chunk_paths)} chunks ingested")

        else:
            log(f"Unsupported file type: {ext}")
            log("   Supported: .md, .txt, .png, .jpg, .jpeg, .mp4")

    except Exception as e:
        log(f"Error: {e}")

    return "\n".join(log_lines)


# -- Gradio app --

with gr.Blocks(title="Multimodal RAG") as demo:
    gr.Markdown("# Multimodal RAG -- Gemini Embedding 2 + pgvector")

    with gr.Tabs():
        with gr.TabItem("Search"):
            gr.Markdown(
                "Search across text documents, images, and video segments "
                "using native multimodal embeddings."
            )
            with gr.Row():
                with gr.Column(scale=3):
                    question = gr.Textbox(
                        label="Question",
                        placeholder="e.g. How do we handle form validation?",
                        lines=2,
                    )
                with gr.Column(scale=1):
                    top_k = gr.Slider(
                        minimum=1, maximum=20, value=5, step=1,
                        label="Results",
                    )
                    source_filter = gr.Radio(
                        choices=["All", "Text", "Image", "Video"],
                        value="All",
                        label="Filter by type",
                    )
            search_btn = gr.Button("Search", variant="primary")

            with gr.Row():
                with gr.Column():
                    answer_output = gr.Markdown(label="Answer")
                with gr.Column():
                    sources_output = gr.Markdown(label="Sources")

            gr.Markdown("### Media Preview")
            with gr.Row():
                with gr.Column():
                    video_preview = gr.Video(label="Top Video Match", visible=True)
                with gr.Column():
                    image_preview = gr.Gallery(
                        label="Matched Images",
                        columns=2,
                        height="auto",
                    )

            search_btn.click(
                fn=search,
                inputs=[question, top_k, source_filter],
                outputs=[answer_output, sources_output, video_preview, image_preview],
            )
            question.submit(
                fn=search,
                inputs=[question, top_k, source_filter],
                outputs=[answer_output, sources_output, video_preview, image_preview],
            )

        with gr.TabItem("Upload & Ingest"):
            gr.Markdown(
                "Upload files to add them to the knowledge base. "
                "Supported: .md, .txt, .pdf, .png, .jpg, .mp4\n\n"
                "Videos are automatically chunked into ~97s segments before embedding."
            )
            file_input = gr.File(
                label="Drop a file here",
                file_types=[".md", ".txt", ".pdf", ".png", ".jpg", ".jpeg", ".mp4"],
            )
            ingest_btn = gr.Button("Ingest", variant="primary")
            ingest_log = gr.Textbox(
                label="Ingestion Log",
                lines=15,
                interactive=False,
            )
            ingest_btn.click(
                fn=ingest_file,
                inputs=[file_input],
                outputs=[ingest_log],
            )

        with gr.TabItem("MCP API"):
            gr.Markdown("API endpoint for MCP clients. Use the `rag_search` tool.")
            mcp_question = gr.Textbox(label="Question")
            mcp_top_k = gr.Number(label="Top K", value=5)
            mcp_output = gr.Textbox(label="Answer", lines=10)
            mcp_btn = gr.Button("Search", variant="primary")
            mcp_btn.click(
                fn=rag_search,
                inputs=[mcp_question, mcp_top_k],
                outputs=[mcp_output],
                api_name="rag_search",
            )

if __name__ == "__main__":
    auth_user = os.environ.get("RAG_AUTH_USER", "admin")
    auth_pass = os.environ.get("RAG_AUTH_PASS")
    auth = (auth_user, auth_pass) if auth_pass else None
    demo.launch(server_name="0.0.0.0", auth=auth, mcp_server=True)
