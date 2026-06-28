"""Watch directories for new files, auto-ingest into RAG, and delete source files after successful ingestion.

Memory files are exempt from deletion (they're part of the Claude memory system).
"""

import os
import sys
import time
import logging
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

from batch_ingest import ingest_one, SUPPORTED

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("rag-watcher")

WATCH_DIR = os.environ.get("RAG_WATCH_DIR", "/mnt/nas/claude/")
SETTLE_SECONDS = 5  # wait for file to finish writing

# Paths containing these substrings are exempt from post-ingest deletion
NO_DELETE_PATHS = ("/watch/memory", "/memory/", "MEMORY.md")


def classify(filepath: str) -> str | None:
    ext = os.path.splitext(filepath)[1].lower()
    for ftype, exts in SUPPORTED.items():
        if ext in exts:
            return ftype
    return None


def is_delete_exempt(filepath: str) -> bool:
    return any(marker in filepath for marker in NO_DELETE_PATHS)


class IngestHandler(FileSystemEventHandler):
    def __init__(self):
        self.pending = {}

    def on_created(self, event):
        if event.is_directory:
            return
        ftype = classify(event.src_path)
        if ftype:
            self.pending[event.src_path] = (time.time(), ftype)
            log.info(f"Detected new file: {event.src_path} ({ftype})")

    def on_modified(self, event):
        if event.is_directory:
            return
        ftype = classify(event.src_path)
        if ftype:
            self.pending[event.src_path] = (time.time(), ftype)

    def process_settled(self):
        now = time.time()
        done = []
        for path, (ts, ftype) in self.pending.items():
            if now - ts < SETTLE_SECONDS:
                continue
            if not os.path.exists(path):
                done.append(path)
                continue
            log.info(f"Ingesting: {path}")
            try:
                ingest_one(path, ftype)
            except Exception as e:
                log.error(f"Failed to ingest {path}: {e}")
                done.append(path)
                continue

            if is_delete_exempt(path):
                log.info(f"Keeping (memory-exempt): {path}")
            else:
                try:
                    os.remove(path)
                    log.info(f"Deleted after ingest: {path}")
                except OSError as e:
                    log.warning(f"Could not delete {path}: {e}")

            done.append(path)
        for p in done:
            del self.pending[p]


def main():
    watch_dirs = sys.argv[1:] if len(sys.argv) > 1 else [WATCH_DIR]

    handler = IngestHandler()
    observer = Observer()

    for d in watch_dirs:
        log.info(f"Watching {d} for new/modified files...")
        observer.schedule(handler, d, recursive=True)

    log.info(f"Supported: {', '.join(ext for exts in SUPPORTED.values() for ext in exts)}")
    observer.start()

    try:
        while True:
            handler.process_settled()
            time.sleep(2)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()


if __name__ == "__main__":
    main()
