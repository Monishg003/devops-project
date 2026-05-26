# DevOps Production Platform

A production-grade containerized platform built as part
of a structured DevOps learning journey.

## Architecture

Internet → Nginx (reverse proxy)
→ App (business logic)
→ PostgreSQL (persistence)
→ Redis (caching)


## Tech Stack

| Component | Technology | Version |
|-----------|------------|---------|
| Reverse Proxy | Nginx | 1.25-alpine |
| Application | Alpine + Bash | 3.18 |
| Database | PostgreSQL | 15-alpine |
| Cache | Redis | 7-alpine |
| Orchestration | Docker Compose | v2 |

## Security Features

- Non-root container user
- Read-only root filesystem
- Capability dropping (--cap-drop ALL)
- No hardcoded secrets (.env pattern)
- Trivy vulnerability scanning
- Security headers in Nginx
- Rate limiting (10 req/s per IP)
- Internal network isolation

## Quick Start

```bash
# Clone and configure
git clone <repo>
cp .env.example .env
# Edit .env with your values

# Deploy
bash scripts/deploy.sh

# Check health
bash scripts/health-check.sh

# View logs
docker compose logs -f

# Stop
docker compose down
```

## Project Structure

.
├── app/                 # Application code
├── nginx/conf/          # Nginx configuration
├── postgres/init/       # Database init scripts
├── scripts/             # Automation scripts
├── docker-compose.yml   # Service definitions
├── .env.example         # Environment template
└── README.md            # This file

## Engineer

**Monish G** — Java Spring Boot Developer → DevOps Engineer
