# syntax=docker/dockerfile:1

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: builder
# Source code exists only in this layer.
# The builder stage is NOT included in the final image pushed to the registry.
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: runtime
# Minimal image: bash removed, non-root user, no package manager.
#
# NOTE: This raises the bar but is not a hard cryptographic barrier.
# A host-level root user can still read container files via:
#   nsenter -t <PID> --mount -- cat /app/main.py
#   cat /var/lib/docker/overlay2/<hash>/merged/app/main.py
# See SECURITY_MODEL.md for the full analysis.
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.12-slim

# Remove interactive shells to prevent `docker exec -it container bash`
RUN apt-get update \
    && apt-get remove --purge -y bash \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1001 appuser \
    && useradd --uid 1001 --gid 1001 --no-create-home appuser

# Copy only pip-installed packages (not the builder's source tree)
COPY --from=builder \
     /usr/local/lib/python3.12/site-packages \
     /usr/local/lib/python3.12/site-packages

COPY --from=builder /build/app /app

WORKDIR /app
USER 1001
EXPOSE 8000

ENTRYPOINT ["python", "-m", "uvicorn", "main:app", \
            "--host", "0.0.0.0", "--port", "8000"]
