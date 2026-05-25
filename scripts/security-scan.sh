#!/bin/bash
set -euo pipefail
# ================================================
# Security scan before deployment
# Fails if critical vulnerabilities found
# ================================================

echo "================================================"
echo " Pre-deployment Security Scan"
echo " $(date)"
echo "================================================"

IMAGES=(
    "devops-final-project-app:latest"
    "nginx:1.25-alpine"
    "postgres:15-alpine"
    "redis:7-alpine"
)

FAILED=0

for IMAGE in "${IMAGES[@]}"; do
    echo ""
    echo "Scanning: $IMAGE"

    # Pull image if needed
    docker pull "$IMAGE" > /dev/null 2>&1 || true

    CRITICAL=$(trivy image \
        --severity CRITICAL \
        --exit-code 0 \
        --quiet \
        --format json \
        "$IMAGE" 2>/dev/null \
        | grep -o '"Severity":"CRITICAL"' \
        | wc -l)

    if [ "$CRITICAL" -gt 0 ]; then
        echo "❌ FAILED: $CRITICAL CRITICAL CVEs in $IMAGE"
        FAILED=$((FAILED+1))
    else
        echo "✅ PASSED: $IMAGE"
    fi
done

echo ""
echo "================================================"
if [ $FAILED -gt 0 ]; then
    echo "❌ Security scan FAILED — $FAILED image(s) blocked"
    exit 1
else
    echo "✅ All images passed security scan"
    exit 0
fi
