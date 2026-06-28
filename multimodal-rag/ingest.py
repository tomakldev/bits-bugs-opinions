"""Ingest text documents, images, and video chunks into pgvector via Gemini (Hybrid API/Vertex)."""

import os
from google import genai
from google.genai import types

from config import GEMINI_API_KEY, EMBEDDING_MODEL, EMBEDDING_DIM, LLM_MODEL, GCP_PROJECT, GCP_LOCATION
from db import insert_parent_document, insert_child_document

# Separate clients for separate purposes
client_api = genai.Client(api_key=GEMINI_API_KEY)
client_vertex = genai.Client(vertexai=True, project=GCP_PROJECT, location=GCP_LOCATION)

def embed_text(text: str) -> list[float]:
    # Use API Key for embeddings
    result = client_api.models.embed_content(
        model=EMBEDDING_MODEL,
        contents=[text],
        config=types.EmbedContentConfig(
            task_type="RETRIEVAL_DOCUMENT",
            output_dimensionality=EMBEDDING_DIM,
        ),
    )
    return result.embeddings[0].values

def embed_pdf_bytes(pdf_bytes: bytes) -> list[float]:
    # Use API Key for embeddings
    result = client_api.models.embed_content(
        model=EMBEDDING_MODEL,
        contents=types.Content(parts=[
            types.Part.from_bytes(data=pdf_bytes, mime_type="application/pdf"),
        ]),
        config=types.EmbedContentConfig(output_dimensionality=EMBEDDING_DIM),
    )
    return result.embeddings[0].values

def describe_content_bytes(data: bytes, mime_type: str) -> str:
    """Use Gemini-2.5-Pro on Vertex AI to generate a text description from raw bytes."""
    response = client_vertex.models.generate_content(
        model=LLM_MODEL,
        contents=types.Content(parts=[
            types.Part.from_bytes(data=data, mime_type=mime_type),
            types.Part.from_text(text="Describe this content in detail for a knowledge base."),
        ]),
    )
    return response.text
