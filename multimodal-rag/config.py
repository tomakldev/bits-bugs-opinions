import os
from dotenv import load_dotenv

load_dotenv()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GCP_PROJECT = os.getenv("PROJECT")
GCP_LOCATION = os.getenv("LOCATION", "europe-west4")

DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT = os.getenv("DB_PORT", "5433")
DB_NAME = os.getenv("DB_NAME", "ragdb")
DB_USER = os.getenv("DB_USER", "raguser")
DB_PASSWORD = os.getenv("DB_PASSWORD")

EMBEDDING_MODEL = "gemini-embedding-2-preview"
EMBEDDING_DIM = 3072
LLM_MODEL = "gemini-2.5-pro"
