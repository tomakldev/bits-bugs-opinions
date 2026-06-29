#!/usr/bin/env bash
# client-deploy.sh — runs on the client machine.
# Logs into the private registry, pulls the latest images, and starts
# the application. Requires .env in the parent directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$APP_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env file not found at $ENV_FILE"
  echo "  Your vendor should have provided a .env file alongside this script."
  exit 1
fi

# shellcheck source=/dev/null
set -a && source "$ENV_FILE" && set +a

# ── Sanity checks ─────────────────────────────────────────────────────────
for var in REGISTRY REGISTRY_USERNAME REGISTRY_PASSWORD LICENSE_KEY; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set in .env — contact your vendor."
    exit 1
  fi
done

# ── Registry login ────────────────────────────────────────────────────────
echo "Logging in to container registry..."
echo "$REGISTRY_PASSWORD" \
  | docker login --username "$REGISTRY_USERNAME" --password-stdin "$REGISTRY"

# ── Pull ──────────────────────────────────────────────────────────────────
echo "Pulling images (version: ${APP_VERSION:-latest})..."
docker compose --file "$APP_DIR/docker-compose.yml" \
               --env-file "$ENV_FILE" \
               pull

# ── Start ─────────────────────────────────────────────────────────────────
echo "Starting application..."
docker compose --file "$APP_DIR/docker-compose.yml" \
               --env-file "$ENV_FILE" \
               up --detach --remove-orphans

echo ""
echo "Application started."
echo "  Frontend: http://localhost:3000"
echo "  Backend:  http://localhost:8000"
echo ""
echo "  Logs:  docker compose logs -f"
echo "  Stop:  docker compose down"
