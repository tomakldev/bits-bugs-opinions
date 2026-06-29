#!/usr/bin/env bash
# build-and-push.sh — vendor-side script.
# Builds backend and frontend Docker images and pushes them to the
# private registry. Run this from the repo root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Configuration ─────────────────────────────────────────────────────────
REGISTRY="${REGISTRY:-}"
REPO_PREFIX="${REPO_PREFIX:-myapp}"
APP_VERSION="${APP_VERSION:-$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo 'latest')}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

# ── Validation ────────────────────────────────────────────────────────────
if [[ -z "$REGISTRY" ]]; then
  echo "ERROR: REGISTRY is not set."
  echo ""
  echo "  Export it or prefix the command:"
  echo "  REGISTRY=123456789.dkr.ecr.us-east-1.amazonaws.com ./scripts/build-and-push.sh"
  exit 1
fi

# ── Registry login ────────────────────────────────────────────────────────
# AWS ECR — adapt this block for other registries:
#   GCR:   gcloud auth configure-docker
#   GHCR:  echo "$GHCR_TOKEN" | docker login ghcr.io -u USERNAME --password-stdin
if [[ "$REGISTRY" == *.dkr.ecr.*.amazonaws.com ]]; then
  echo "Authenticating with AWS ECR..."
  REGION=$(echo "$REGISTRY" | grep -oP '(?<=dkr.ecr.)([^.]+)')
  aws ecr get-login-password --region "$REGION" \
    | docker login --username AWS --password-stdin "$REGISTRY"
fi

BACKEND_IMAGE="$REGISTRY/$REPO_PREFIX/backend:$APP_VERSION"
FRONTEND_IMAGE="$REGISTRY/$REPO_PREFIX/frontend:$APP_VERSION"

echo ""
echo "Building for platforms: $PLATFORMS"
echo "  $BACKEND_IMAGE"
echo "  $FRONTEND_IMAGE"
echo ""

# Ensure buildx builder with multi-platform support exists
docker buildx inspect myapp-builder > /dev/null 2>&1 \
  || docker buildx create --name myapp-builder --use

# ── Backend ───────────────────────────────────────────────────────────────
docker buildx build \
  --platform "$PLATFORMS" \
  --push \
  --tag "$BACKEND_IMAGE" \
  --tag "$REGISTRY/$REPO_PREFIX/backend:latest" \
  --file "$REPO_ROOT/backend/Dockerfile" \
  --cache-from "type=registry,ref=$REGISTRY/$REPO_PREFIX/backend:cache" \
  --cache-to "type=registry,ref=$REGISTRY/$REPO_PREFIX/backend:cache,mode=max" \
  "$REPO_ROOT/backend"

# ── Frontend ──────────────────────────────────────────────────────────────
docker buildx build \
  --platform "$PLATFORMS" \
  --push \
  --tag "$FRONTEND_IMAGE" \
  --tag "$REGISTRY/$REPO_PREFIX/frontend:latest" \
  --file "$REPO_ROOT/frontend/Dockerfile" \
  --cache-from "type=registry,ref=$REGISTRY/$REPO_PREFIX/frontend:cache" \
  --cache-to "type=registry,ref=$REGISTRY/$REPO_PREFIX/frontend:cache,mode=max" \
  "$REPO_ROOT/frontend"

echo ""
echo "Done. Pushed:"
echo "  $BACKEND_IMAGE"
echo "  $FRONTEND_IMAGE"
echo ""
echo "Next step: generate client credentials with ./scripts/rotate-creds.sh"
