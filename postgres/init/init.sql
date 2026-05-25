-- Initial database setup
-- Runs automatically when postgres container first starts

CREATE TABLE IF NOT EXISTS app_requests (
    id          SERIAL PRIMARY KEY,
    endpoint    VARCHAR(255) NOT NULL,
    method      VARCHAR(10) DEFAULT 'GET',
    status_code INT DEFAULT 200,
    response_ms INT DEFAULT 0,
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app_health (
    id         SERIAL PRIMARY KEY,
    status     VARCHAR(50) NOT NULL,
    checked_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS deployments (
    id          SERIAL PRIMARY KEY,
    version     VARCHAR(50) NOT NULL,
    deployed_by VARCHAR(100) DEFAULT 'monish',
    deployed_at TIMESTAMP DEFAULT NOW(),
    status      VARCHAR(50) DEFAULT 'active'
);

-- Seed initial data
INSERT INTO deployments (version, status)
VALUES ('1.0.0', 'active');

-- Create read-only user for reporting
CREATE USER reporter WITH PASSWORD 'reporter123';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO reporter;
