#!/usr/bin/env bash
# rotate-creds.sh — vendor-side script.
# Generates fresh pull credentials for a client and prints the .env
# contents to send them. Rotate before existing credentials expire.
#
# For AWS ECR: tokens are valid for 12 hours. For a production setup,
# consider an IAM user with a pull-only ECR policy instead of short-lived
# tokens — easier to rotate on a schedule and auditable per client.
set -euo pipefail

REGISTRY="${REGISTRY:-}"
LICENSE_KEY="${LICENSE_KEY:-}"
LICENSE_SERVER_URL="${LICENSE_SERVER_URL:-https://license.yourdomain.com}"
APP_VERSION="${APP_VERSION:-latest}"

if [[ -z "$REGISTRY" ]]; then
  echo "ERROR: REGISTRY not set." >&2
  exit 1
fi

# Generate a license key if one isn't provided
if [[ -z "$LICENSE_KEY" ]]; then
  LICENSE_KEY=$(openssl rand -hex 20)
  echo "Generated new license key: $LICENSE_KEY" >&2
  echo "Register this key in your license server before sending to client." >&2
  echo "" >&2
fi

# ── Get registry credentials ──────────────────────────────────────────────
if [[ "$REGISTRY" == *.dkr.ecr.*.amazonaws.com ]]; then
  REGISTRY_USERNAME="AWS"
  REGION=$(echo "$REGISTRY" | grep -oP '(?<=dkr.ecr.)([^.]+)')
  REGISTRY_PASSWORD=$(aws ecr get-login-password --region "$REGION")
  EXPIRES=$(date -d "+12 hours" "+%Y-%m-%d %H:%M UTC" 2>/dev/null \
            || date -v+12H "+%Y-%m-%d %H:%M UTC")
else
  echo "ERROR: Unsupported registry. Adapt this script for your registry provider." >&2
  exit 1
fi

# ── Print .env to stdout ──────────────────────────────────────────────────
cat <<ENV
# Generated: $(date -u '+%Y-%m-%d %H:%M UTC')
# Expires:   $EXPIRES
# Send this file to the client as .env alongside docker-compose.yml

# Registry access
REGISTRY=$REGISTRY
REGISTRY_USERNAME=$REGISTRY_USERNAME
REGISTRY_PASSWORD=$REGISTRY_PASSWORD

# Application
APP_VERSION=$APP_VERSION

# License
LICENSE_KEY=$LICENSE_KEY
LICENSE_SERVER_URL=$LICENSE_SERVER_URL
ENV
