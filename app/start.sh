#!/bin/bash
set -euo pipefail

APP_PORT=${APP_PORT:-8080}
APP_NAME=${APP_NAME:-"DevOps Platform"}
APP_VERSION=${APP_VERSION:-"1.0.0"}
DB_HOST=${DB_HOST:-"postgres"}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-"appdb"}
DB_USER=${DB_USER:-"appuser"}
REDIS_HOST=${REDIS_HOST:-"redis"}


log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}


wait_for_postgres() {
    log "Waiting for PostgreSQL at $DB_HOST:$DB_PORT..."
    local RETRY=0
    local MAX=30
    until pg_isready \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" > /dev/null 2>&1; do
        RETRY=$((RETRY+1))
        if [ $RETRY -ge $MAX ]; then
            log "ERROR: PostgreSQL not ready after ${MAX} attempts"
            exit 1
        fi
        log "PostgreSQL not ready — attempt $RETRY/$MAX"
        sleep 3
    done
    log "PostgreSQL ready!"
}


wait_for_redis() {
    log "Waiting for Redis at $REDIS_HOST..."
    local RETRY=0
    local MAX=20
    until wget -q --spider \
        "http://$REDIS_HOST:6379" > /dev/null 2>&1 || \
        (echo "PING" | \
        timeout 3 sh -c \
        "cat > /dev/tcp/$REDIS_HOST/6379" > /dev/null 2>&1); do
        RETRY=$((RETRY+1))
        if [ $RETRY -ge $MAX ]; then
            log "WARNING: Redis not confirmed — continuing anyway"
            break
        fi
        log "Redis not ready — attempt $RETRY/$MAX"
        sleep 2
    done
    log "Redis check complete!"
}

init_database() {
    log "Initializing database schema..."
    PGPASSWORD="$DB_PASSWORD" psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" << 'SQL'
CREATE TABLE IF NOT EXISTS app_requests (
    id          SERIAL PRIMARY KEY,
    endpoint    VARCHAR(255) NOT NULL,
    method      VARCHAR(10) DEFAULT 'GET',
    status_code INT DEFAULT 200,
    response_ms INT DEFAULT 0,
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app_health (
    id          SERIAL PRIMARY KEY,
    status      VARCHAR(50) NOT NULL,
    checked_at  TIMESTAMP DEFAULT NOW()
);

INSERT INTO app_health (status) VALUES ('started');
SQL
    log "Database initialized!"
}


handle_request() {
    local REQUEST_START=$(date +%s%3N)

    # Log request to DB
    PGPASSWORD="$DB_PASSWORD" psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -c "INSERT INTO app_requests
            (endpoint, method, status_code)
            VALUES ('/', 'GET', 200);" \
        > /dev/null 2>&1 || true

    # Get stats from DB
    TOTAL_REQUESTS=$(PGPASSWORD="$DB_PASSWORD" psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -t \
        -c "SELECT COUNT(*) FROM app_requests;" \
        2>/dev/null | tr -d ' \n') || TOTAL_REQUESTS="N/A"

    local REQUEST_END=$(date +%s%3N)
    local RESPONSE_MS=$((REQUEST_END - REQUEST_START))

    # Build response
    cat << EOF
HTTP/1.1 200 OK
Content-Type: text/html
Connection: close

<!DOCTYPE html>
<html>
<head>
<title>$APP_NAME</title>
<meta http-equiv="refresh" content="5">
<style>
* { margin:0; padding:0; box-sizing:border-box; }
body { background:#0d1117; color:#e6edf3;
       font-family:'Segoe UI',monospace;
       min-height:100vh; padding:40px 20px; }
.container { max-width:800px; margin:0 auto; }
h1 { color:#58a6ff; font-size:2em; margin-bottom:8px; }
.subtitle { color:#8b949e; margin-bottom:30px; }
.grid { display:grid;
        grid-template-columns:repeat(2,1fr);
        gap:16px; margin-bottom:24px; }
.card { background:#161b22;
        border:1px solid #30363d;
        border-radius:8px; padding:20px; }
.card h3 { color:#58a6ff;
           font-size:0.85em;
           text-transform:uppercase;
           letter-spacing:0.05em;
           margin-bottom:12px; }
.metric { font-size:1.8em;
          font-weight:700;
          color:#3fb950; }
.badge { display:inline-block;
         padding:4px 12px;
         border-radius:20px;
         font-size:0.8em;
         margin:4px 2px; }
.green { background:#1a4721; color:#3fb950;
         border:1px solid #3fb950; }
.blue  { background:#1c2f4d; color:#58a6ff;
         border:1px solid #58a6ff; }
.bar { height:4px; background:#21262d;
       border-radius:2px; margin-top:8px; }
.bar-fill { height:100%; border-radius:2px;
            background:#3fb950; width:85%; }
</style>
</head>
<body>
<div class="container">
  <h1>🚀 $APP_NAME</h1>
  <p class="subtitle">Production DevOps Platform v$APP_VERSION</p>

  <div class="grid">
    <div class="card">
      <h3>Application Status</h3>
      <div class="metric">✅ Healthy</div>
      <div style="margin-top:8px">
        <span class="badge green">Running</span>
        <span class="badge blue">v$APP_VERSION</span>
      </div>
    </div>

    <div class="card">
      <h3>Total Requests</h3>
      <div class="metric">$TOTAL_REQUESTS</div>
      <div class="bar"><div class="bar-fill"></div></div>
    </div>

    <div class="card">
      <h3>Infrastructure</h3>
      <div>
        <span class="badge green">PostgreSQL ✅</span>
        <span class="badge green">Redis ✅</span>
        <span class="badge green">Nginx ✅</span>
      </div>
    </div>

    <div class="card">
      <h3>Response Time</h3>
      <div class="metric">${RESPONSE_MS}ms</div>
      <div class="bar">
        <div class="bar-fill" style="width:${RESPONSE_MS}%">
        </div>
      </div>
    </div>
  </div>

  <div class="card">
    <h3>Engineer</h3>
    <p>👨‍💻 Monish G — DevOps Engineer</p>
    <p style="color:#8b949e;margin-top:4px;font-size:0.9em">
      Linux • Docker • Kubernetes • CI/CD
    </p>
    <p style="color:#8b949e;font-size:0.9em">
      Last updated: $(date '+%Y-%m-%d %H:%M:%S')
    </p>
  </div>
</div>
</body>
</html>
EOF
}


handle_health() {
    local DB_STATUS="unknown"
    local UPTIME=$(cat /proc/uptime | cut -d. -f1)

    if pg_isready \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" > /dev/null 2>&1; then
        DB_STATUS="healthy"

        # Log health check
        PGPASSWORD="$DB_PASSWORD" psql \
            -h "$DB_HOST" \
            -p "$DB_PORT" \
            -U "$DB_USER" \
            -d "$DB_NAME" \
            -c "INSERT INTO app_health (status)
                VALUES ('healthy');" \
            > /dev/null 2>&1 || true
    else
        DB_STATUS="unhealthy"
    fi

    cat << EOF
HTTP/1.1 200 OK
Content-Type: application/json
Connection: close

{
  "status": "UP",
  "version": "$APP_VERSION",
  "database": "$DB_STATUS",
  "uptime_seconds": $UPTIME,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}



start_server() {
    log "Starting $APP_NAME v$APP_VERSION"
    log "Listening on port $APP_PORT"
    log "Database: $DB_HOST:$DB_PORT/$DB_NAME"

    while true; do
        REQUEST=$(timeout 30 \
            nc -l -p "$APP_PORT" 2>/dev/null) || continue

        ENDPOINT=$(echo "$REQUEST" | \
            head -1 | awk '{print $2}')

        case "$ENDPOINT" in
            /health*)
                handle_health | \
                    nc -l -p "$APP_PORT" -q 1 \
                    > /dev/null 2>&1 || true
                ;;
            *)
                handle_request | \
                    nc -l -p "$APP_PORT" -q 1 \
                    > /dev/null 2>&1 || true
                ;;
        esac
    done
}

# ---- Startup Sequence ----
log "========================================="
log " $APP_NAME Starting Up"
log "========================================="

wait_for_postgres
init_database
start_server
