# Secure App Deployment with Docker

A Docker-based deployment setup for distributing a Python + Next.js application to client environments where the client has root access on their server.

## What this is

The client (your customer) has a machine. You want to run your software on it. The problem: you can't trust them not to look at your source code. This setup makes that materially harder — and explains clearly where the protection ends.

## Structure

```
.
├── backend/                 Python FastAPI application
│   ├── Dockerfile           Multi-stage: builder + slim runtime (no shell)
│   ├── .dockerignore
│   ├── requirements.txt
│   └── app/
│       ├── main.py          Sample app — replace with your code
│       └── license_check.py Startup license validation
├── frontend/                Next.js application
│   ├── Dockerfile           Multi-stage: node builder + standalone runtime
│   ├── .dockerignore
│   └── next.config.js       Enables standalone output mode
├── nginx/
│   └── nginx.conf           Optional reverse proxy
├── scripts/
│   ├── build-and-push.sh    Vendor: build images + push to private registry
│   ├── rotate-creds.sh      Vendor: generate fresh client pull credentials
│   └── client-deploy.sh     Client: pull images and start the app
├── docker-compose.yml       Client-facing: image references only, no source
├── docker-compose.build.yml Vendor-facing: build configuration
├── .env.example             Client .env template
└── SECURITY_MODEL.md        Threat model and honest limitations
```

## How the model works

**You (vendor)** own the registry. You build images from source and push them. The client never sees a `git clone`, a `requirements.txt install`, or a `node_modules/`. They get only the finished image — and only while you give them credentials to pull it.

**Client** gets three things:
1. `docker-compose.yml` — image references and port mappings, nothing more
2. `.env` file — time-limited credentials you generated
3. `client-deploy.sh` — logs them into the registry, pulls, and starts

When the contract ends, stop issuing credentials. The image cached on their disk remains (you can't reach in and delete it), but they can't pull updates.

## Prerequisites

- **Vendor**: Docker, AWS CLI (for ECR), `docker buildx`
- **Client**: Docker + Docker Compose, `.env` file from vendor

## Quickstart (vendor side)

```bash
# 1. Set your registry in scripts/build-and-push.sh
export REGISTRY="123456789.dkr.ecr.us-east-1.amazonaws.com"
export REPO_PREFIX="myapp"

# 2. Build and push
./scripts/build-and-push.sh

# 3. Generate client credentials (prints .env contents to send)
./scripts/rotate-creds.sh
```

## Quickstart (client side)

```bash
# Place the .env file from vendor in this directory, then:
chmod +x scripts/client-deploy.sh
./scripts/client-deploy.sh
```

App runs at:
- Frontend: `http://localhost:3000`
- Backend API: `http://localhost:8000`

## Important

Read [SECURITY_MODEL.md](./SECURITY_MODEL.md) before deploying. It explains what this setup actually protects and where the model breaks down. Skipping it leads to false confidence.

## Frontend note

The frontend Dockerfile assumes `output: 'standalone'` in `next.config.js` (included). Copy your Next.js app source into `frontend/` alongside the Dockerfile before building. The build stage compiles TypeScript and produces a self-contained server — no source `.ts` or `.tsx` files land in the final image, only compiled JavaScript.
