# syntax=docker/dockerfile:1

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: builder
# TypeScript source exists only in this layer.
# Requires next.config.js to have `output: 'standalone'`.
# ─────────────────────────────────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /build

# Install dependencies first (better layer caching)
COPY package*.json ./
RUN npm ci --ignore-scripts

COPY . .
RUN npm run build

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: runtime
# Standalone Next.js output only — no source .ts/.tsx files.
#
# NOTE: The .next/static directory contains compiled/minified JavaScript
# served to the browser. While TypeScript source is absent, the business
# logic in client-side code is present in minified form and can be read.
# Server-side logic (API routes, server components) is bundled into
# server.js and is harder to read but not cryptographically protected.
# See SECURITY_MODEL.md.
# ─────────────────────────────────────────────────────────────────────────────
FROM node:20-alpine AS runtime

RUN addgroup -g 1001 -S nodejs \
    && adduser -S -u 1001 nextjs

WORKDIR /app

# standalone/ contains a self-contained server with only required node_modules
COPY --from=builder --chown=nextjs:nodejs /build/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /build/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /build/public ./public

USER nextjs
EXPOSE 3000

ENV PORT=3000
ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0

CMD ["node", "server.js"]
