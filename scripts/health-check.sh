#!/bin/bash
# ================================================
# Full stack health check
# ================================================

BASE_URL="http://localhost:${NGINX_PORT:-9999}"

echo "================================================"
echo " Stack Health Check"
echo " $(date)"
echo "================================================"

PASS=0
FAIL=0

check() {
    local NAME=$1
    local URL=$2
    local EXPECTED=$3

    RESULT=$(curl -s --max-time 5 "$URL" 2>/dev/null)
    if echo "$RESULT" | grep -q "$EXPECTED"; then
        echo "✅ $NAME"
        PASS=$((PASS+1))
    else
        echo "❌ $NAME (expected: $EXPECTED)"
        FAIL=$((FAIL+1))
    fi
}

check_stats() {
    local NAME=$1
    local URL=$2

    RESULT=$(curl -s --max-time 5 "$URL" 2>/dev/null)

    TOTAL_REQUESTS=$(echo "$RESULT" | \
        grep -o '"total_requests": "[0-9]*"' | \
        grep -o '[0-9]*')

    if [ -n "$TOTAL_REQUESTS" ]; then
        echo "✅ $NAME | total requests = $TOTAL_REQUESTS"
        PASS=$((PASS+1))
    else
        echo "❌ $NAME check failed"
        FAIL=$((FAIL+1))
    fi
}

# Check all endpoints
check "Nginx health"  \
    "$BASE_URL/nginx-health" "nginx"
check "App health"    \
    "$BASE_URL/health" "UP"
check "Main page"     \
    "$BASE_URL" "DevOps Platform"
check "DB connected"  \
    "$BASE_URL/health" "healthy"
check_stats "Metrics / stats" \
    "$BASE_URL/stats"

# Check containers
echo ""
echo "Container Status:"
for NAME in devops-postgres devops-redis \
            devops-app devops-nginx; do
    STATUS=$(docker inspect \
        --format='{{.State.Status}}' \
        "$NAME" 2>/dev/null || echo "not found")
    if [ "$STATUS" = "running" ]; then
        echo "✅ $NAME: running"
        PASS=$((PASS+1))
    else
        echo "❌ $NAME: $STATUS"
        FAIL=$((FAIL+1))
    fi
done

echo ""
echo "================================================"
echo " Results: $PASS passed / $FAIL failed"
echo "================================================"

[ $FAIL -eq 0 ] && exit 0 || exit 1
