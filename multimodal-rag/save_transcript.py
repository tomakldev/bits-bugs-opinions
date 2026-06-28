"""Save Claude Code conversation transcripts to RAG as exchange pairs.

Each user+assistant turn becomes a separate document for granular search.
Turns are auto-classified into: decision, preference, milestone, problem, emotional, general.

Usage:
    python save_transcript.py /path/to/transcript.jsonl [session_id] [event]
"""

import sys
import os
import json
import time
from datetime import datetime

from ingest import embed_text
from db import insert_document
from classify import classify_turn

MAX_PAIR_LENGTH = 8_000  # ~2.5K tokens per pair, safe for 10K embedding limit
BATCH_SIZE = 5  # pairs per batch
BATCH_PAUSE = 3  # seconds between batches
RETRY_PAUSE = 30  # seconds on 429


def _extract_text(content) -> str:
    """Extract plain text from a message content field."""
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, str):
                parts.append(block)
            elif isinstance(block, dict):
                text = block.get("text", "")
                if text:
                    parts.append(text)
        return "\n".join(parts).strip()
    return ""


def _parse_entries(transcript_path):
    """Parse transcript JSONL into (type, text) list."""
    messages = []
    try:
        with open(transcript_path) as f:
            for raw_line in f:
                raw_line = raw_line.strip()
                if not raw_line:
                    continue
                try:
                    entry = json.loads(raw_line)
                except json.JSONDecodeError:
                    continue

                entry_type = entry.get("type", "")
                if entry_type not in ("user", "assistant"):
                    continue

                message = entry.get("message")
                if isinstance(message, dict):
                    content = _extract_text(message.get("content", ""))
                else:
                    content = _extract_text(entry.get("content", ""))

                if not content:
                    continue
                if content.startswith(("<system-reminder>", "<task-notification>", "<local-command-caveat>")):
                    continue

                messages.append((entry_type, content))
    except (OSError, IOError):
        pass
    return messages


def extract_turn_pairs(transcript_path):
    """Extract (turn_number, user_text, assistant_text) from transcript.

    Groups consecutive assistant messages together (tool use produces multiple
    assistant entries per user turn).
    """
    messages = _parse_entries(transcript_path)
    pairs = []
    turn = 0
    i = 0
    while i < len(messages):
        if messages[i][0] == "user":
            user_text = messages[i][1]
            # Collect all consecutive assistant messages
            assistant_parts = []
            j = i + 1
            while j < len(messages) and messages[j][0] == "assistant":
                assistant_parts.append(messages[j][1])
                j += 1
            if assistant_parts:
                assistant_text = "\n\n".join(assistant_parts)
                pairs.append((turn, user_text, assistant_text))
                turn += 1
                i = j
            else:
                i += 1
        else:
            i += 1
    return pairs


def _embed_with_retry(text):
    """Embed text with retry on rate limit."""
    for attempt in range(3):
        try:
            return embed_text(text)
        except Exception as e:
            if "429" in str(e) and attempt < 2:
                time.sleep(RETRY_PAUSE * (attempt + 1))
                continue
            raise
    return None


def save_transcript(transcript_path, session_id="", event="stop"):
    """Save transcript as exchange pairs to RAG."""
    pairs = extract_turn_pairs(transcript_path)
    if not pairs:
        return

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    date_slug = datetime.now().strftime("%Y%m%d-%H%M")
    today = datetime.now().strftime("%Y-%m-%d")

    # Derive session title from first user message
    first_user = pairs[0][1][:80] if pairs else ""
    session_title = f"Session {date_slug}: {first_user}" if first_user else f"Session {date_slug}"

    saved = 0
    for i, (turn_num, user_text, assistant_text) in enumerate(pairs):
        # Cap pair length (truncate assistant first)
        combined = f"USER: {user_text}\n\nASSISTANT: {assistant_text}"
        if len(combined) > MAX_PAIR_LENGTH:
            max_asst = MAX_PAIR_LENGTH - len(user_text) - 20
            if max_asst < 200:
                max_asst = 200
                user_text = user_text[:MAX_PAIR_LENGTH - 220]
            assistant_text = assistant_text[:max_asst] + " [truncated]"
            combined = f"USER: {user_text}\n\nASSISTANT: {assistant_text}"

        classification = classify_turn(user_text, assistant_text)

        # Skip general turns -- only save decision, problem, milestone, preference, emotional
        if classification == "general":
            continue

        vector = _embed_with_retry(combined)
        if vector is None:
            continue

        source_file = f"session-{date_slug}-turn{turn_num:03d}.md"
        insert_document(
            content=combined,
            embedding=vector,
            source_type="transcript",
            source_file=source_file,
            chunk_index=turn_num,
            metadata={
                "type": "session-turn",
                "session_title": session_title,
                "session_id": session_id,
                "event": event,
                "turn": turn_num,
                "classification": classification,
                "timestamp": timestamp,
                "tags": f"session,transcript,{classification}",
            },
            event_date=today,
        )
        saved += 1

        # Rate limit: pause every BATCH_SIZE pairs
        if (i + 1) % BATCH_SIZE == 0:
            time.sleep(BATCH_PAUSE)

    if saved:
        print(f"Saved {saved}/{len(pairs)} turns: {session_title}")


MIN_TURNS = 5  # skip trivial sessions
QUEUE_DIR = "/home/tomakl/projects/multimodal-rag/transcript_queue"


def queue_transcript(transcript_path, session_id="", event="stop"):
    """Queue a transcript for async processing instead of embedding inline."""
    os.makedirs(QUEUE_DIR, exist_ok=True)
    job = {
        "transcript_path": transcript_path,
        "session_id": session_id,
        "event": event,
        "queued_at": datetime.now().isoformat(),
    }
    job_file = os.path.join(QUEUE_DIR, f"{session_id or 'unknown'}.json")
    with open(job_file, "w") as f:
        json.dump(job, f)
    print(f"Queued transcript: {job_file}")


def process_queue():
    """Process all queued transcripts. Run from cron or systemd timer."""
    if not os.path.isdir(QUEUE_DIR):
        return
    for fname in sorted(os.listdir(QUEUE_DIR)):
        if not fname.endswith(".json"):
            continue
        job_path = os.path.join(QUEUE_DIR, fname)
        try:
            with open(job_path) as f:
                job = json.load(f)
            pairs = extract_turn_pairs(job["transcript_path"])
            if len(pairs) < MIN_TURNS:
                print(f"Skipping {fname}: only {len(pairs)} turns (min {MIN_TURNS})")
                os.remove(job_path)
                continue
            save_transcript(job["transcript_path"], job.get("session_id", ""), job.get("event", "stop"))
            os.remove(job_path)
        except Exception as e:
            print(f"Error processing {fname}: {e}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python save_transcript.py /path/to/transcript.jsonl [session_id] [event]")
        print("       python save_transcript.py --process-queue")
        sys.exit(1)

    if sys.argv[1] == "--process-queue":
        process_queue()
    elif sys.argv[1] == "--queue":
        path = sys.argv[2]
        sid = sys.argv[3] if len(sys.argv) > 3 else ""
        evt = sys.argv[4] if len(sys.argv) > 4 else "stop"
        # Quick check: skip if too few turns
        pairs = extract_turn_pairs(path)
        if len(pairs) < MIN_TURNS:
            print(f"Skipping: only {len(pairs)} turns (min {MIN_TURNS})")
        else:
            queue_transcript(path, sid, evt)
    else:
        path = sys.argv[1]
        sid = sys.argv[2] if len(sys.argv) > 2 else ""
        evt = sys.argv[3] if len(sys.argv) > 3 else "stop"
        save_transcript(path, sid, evt)
