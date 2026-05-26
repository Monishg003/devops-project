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

# ---- Wait for PostgreSQL ----
wait_for_postgres() {
    log "Waiting for PostgreSQL at $DB_HOST:$DB_PORT..."
    local RETRY=0
    until pg_isready \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" > /dev/null 2>&1; do
        RETRY=$((RETRY+1))
        if [ $RETRY -ge 30 ]; then
            log "ERROR: PostgreSQL not ready"
            exit 1
        fi
        sleep 3
    done
    log "PostgreSQL ready!"
}

# ---- Initialize Database ----
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
    created_at  TIMESTAMP DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS app_health (
    id         SERIAL PRIMARY KEY,
    status     VARCHAR(50) NOT NULL,
    checked_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO app_health (status) VALUES ('started');
SQL
    log "Database initialized!"
}

# ---- Generate Python HTTP Server ----
generate_server() {
    log "Generating HTTP server..."

    cat > /tmp/server.py << PYEOF
import http.server
import json
import subprocess
import os
import time
from datetime import datetime

APP_NAME = os.environ.get('APP_NAME', 'DevOps Platform')
APP_VERSION = os.environ.get('APP_VERSION', '1.0.0')
DB_HOST = os.environ.get('DB_HOST', 'postgres')
DB_PORT = os.environ.get('DB_PORT', '5432')
DB_NAME = os.environ.get('DB_NAME', 'appdb')
DB_USER = os.environ.get('DB_USER', 'appuser')
DB_PASSWORD = os.environ.get('DB_PASSWORD', '')
SERVER_START_TIME = time.time()

def get_request_count():
    try:
        env = os.environ.copy()
        env['PGPASSWORD'] = DB_PASSWORD
        result = subprocess.run(
            ['psql', '-h', DB_HOST, '-p', DB_PORT,
             '-U', DB_USER, '-d', DB_NAME,
             '-t', '-c',
             'SELECT COUNT(*) FROM app_requests;'],
            capture_output=True, text=True,
            env=env, timeout=5
        )
        return result.stdout.strip()
    except:
        return 'N/A'

def log_request(endpoint):
    try:
        env = os.environ.copy()
        env['PGPASSWORD'] = DB_PASSWORD
        subprocess.run(
            ['psql', '-h', DB_HOST, '-p', DB_PORT,
             '-U', DB_USER, '-d', DB_NAME,
             '-c',
             f"INSERT INTO app_requests (endpoint) VALUES ('{endpoint}');"],
            capture_output=True, env=env, timeout=5
        )
    except:
        pass

def get_total_health_checks():
    try:
        env = os.environ.copy()
        env['PGPASSWORD'] = DB_PASSWORD

        result = subprocess.run(
            ['psql', '-h', DB_HOST, '-p', DB_PORT,
             '-U', DB_USER, '-d', DB_NAME,
             '-t', '-c',
             'SELECT COUNT(*) FROM app_health;'],
            capture_output=True,
            text=True,
            env=env,
            timeout=5
        )

        return result.stdout.strip()

    except:
        return 'N/A'

def get_latest_requests():
    try:
        env = os.environ.copy()
        env['PGPASSWORD'] = DB_PASSWORD

        result = subprocess.run(
            ['psql', '-h', DB_HOST, '-p', DB_PORT,
             '-U', DB_USER, '-d', DB_NAME,
             '-t', '-c',
             'SELECT endpoint, created_at '
             'FROM app_requests '
             'ORDER BY created_at DESC '
             'LIMIT 2;'],
            capture_output=True,
            text=True,
            env=env,
            timeout=5
        )

        return result.stdout.strip()

    except:
        return 'N/A'

def check_db():
    try:
        result = subprocess.run(
            ['pg_isready', '-h', DB_HOST,
             '-p', DB_PORT, '-U', DB_USER],
            capture_output=True, timeout=5
        )
        return 'healthy' if result.returncode == 0 \
            else 'unhealthy'
    except:
        return 'unhealthy'

class AppHandler(http.server.BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        print(f"[{datetime.now().strftime('%H:%M:%S')}]"
              f" {args[0]} {args[1]}")

    def send_json(self, data, code=200):
        body = json.dumps(data, indent=2).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(body))
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, html, code=200):
        body = html.encode()
        self.send_response(code)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', len(body))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == '/health' or \
           self.path.startswith('/health?'):
            db_status = check_db()
            self.send_json({
                'status': 'UP',
                'version': APP_VERSION,
                'database': db_status,
                'timestamp': datetime.utcnow().isoformat()
            })

        elif self.path == '/metrics':
            uptime = int(time.time() - SERVER_START_TIME)
            self.send_json({
                'total_requests': get_request_count(),
                'total_health_checks': get_total_health_checks(),
                'latest_requests': get_latest_requests(),
                'database': check_db(),
                'uptime_seconds': uptime
            })

        elif self.path == '/':
            log_request('/')
            count = get_request_count()
            html = f"""<!DOCTYPE html>
<html>
<head>
<title>{APP_NAME}</title>
<meta http-equiv="refresh" content="5">
<style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{background:#0d1117;color:#e6edf3;
     font-family:'Segoe UI',monospace;
     min-height:100vh;padding:40px 20px}}
.container{{max-width:800px;margin:0 auto}}
h1{{color:#58a6ff;font-size:2em;margin-bottom:8px}}
.subtitle{{color:#8b949e;margin-bottom:30px}}
.grid{{display:grid;
       grid-template-columns:repeat(2,1fr);
       gap:16px;margin-bottom:24px}}
.card{{background:#161b22;
       border:1px solid #30363d;
       border-radius:8px;padding:20px}}
.card h3{{color:#58a6ff;font-size:.85em;
          text-transform:uppercase;
          margin-bottom:12px}}
.metric{{font-size:1.8em;font-weight:700;
         color:#3fb950}}
.badge{{display:inline-block;padding:4px 12px;
        border-radius:20px;font-size:.8em;
        margin:4px 2px}}
.green{{background:#1a4721;color:#3fb950;
        border:1px solid #3fb950}}
.blue{{background:#1c2f4d;color:#58a6ff;
       border:1px solid #58a6ff}}
</style>
</head>
<body>
<div class="container">
  <h1>🚀 {APP_NAME}</h1>
  <p class="subtitle">
    Production DevOps Platform v{APP_VERSION}
  </p>
  <div class="grid">
    <div class="card">
      <h3>Application Status</h3>
      <div class="metric">✅ Healthy</div>
      <div style="margin-top:8px">
        <span class="badge green">Running</span>
        <span class="badge blue">v{APP_VERSION}</span>
      </div>
    </div>
    <div class="card">
      <h3>Total Requests</h3>
      <div class="metric">{count}</div>
    </div>
    <div class="card">
      <h3>Infrastructure</h3>
      <span class="badge green">PostgreSQL ✅</span>
      <span class="badge green">Redis ✅</span>
      <span class="badge green">Nginx ✅</span>
    </div>
    <div class="card">
      <h3>Engineer</h3>
      <p>👨‍💻 Monish G</p>
      <p style="color:#8b949e;font-size:.9em">
        Java Developer → DevOps Engineer
      </p>
    </div>
  </div>
  <div class="card">
    <h3>Last Updated</h3>
    <p>{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
  </div>
</div>
</body>
</html>"""
            self.send_html(html)
        else:
            self.send_json({'error': 'not found'}, 404)

PORT = int(os.environ.get('APP_PORT', 8080))
server = http.server.HTTPServer(('0.0.0.0', PORT), AppHandler)
print(f"[{datetime.now().strftime('%H:%M:%S')}]"
      f" Server running on port {PORT}")
server.serve_forever()
PYEOF

    log "Server generated at /tmp/server.py"
}

# ---- Startup ----
log "========================================="
log " $APP_NAME Starting Up"
log "========================================="

wait_for_postgres
init_database
generate_server

log "Starting $APP_NAME v$APP_VERSION on port $APP_PORT"
log "Database: $DB_HOST:$DB_PORT/$DB_NAME"

exec python3 /tmp/server.py
