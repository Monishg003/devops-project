#!/bin/bash
set -euo pipefail

# ================================================
# Production Deployment Script
# ================================================

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

log "Starting deployment..."

# Build images first
log "Building images..."
docker compose build --no-cache

# Run security scan
log "Running security scan..."
bash scripts/security-scan.sh

# Deploy stack
log "Deploying stack..."
docker compose up -d

# Verify deployment
log "Checking container status..."
docker compose ps

log "Deployment completed successfully!"
