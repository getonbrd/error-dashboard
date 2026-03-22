# Getting Started

## Prerequisites

- Ruby 3.4+
- PostgreSQL 14+
- A Slack workspace (optional, for notifications)

## Local Development

```bash
git clone https://github.com/getonbrd/error-dashboard.git
cd error-dashboard
bin/setup          # installs gems, creates database
bin/rails db:migrate
bin/dev            # starts Rails + Solid Queue
```

The dashboard is available at `http://localhost:3000/error_dashboard`.

Default credentials: `admin` / `changeme`.

## Docker

### Build

```bash
docker build -t error-dashboard .
```

### Run

```bash
docker run -p 3000:80 \
  -e DATABASE_URL="postgres://user:pass@host:5432/error_dashboard_production" \
  -e SECRET_KEY_BASE="your-secret-key" \
  -e API_BEARER_TOKEN="your-api-token" \
  -e DASHBOARD_USERNAME="admin" \
  -e DASHBOARD_PASSWORD="your-password" \
  error-dashboard
```

The container exposes port 80 by default. Puma runs with Solid Queue embedded (no separate worker process needed).

### Running Migrations

Migrations are **not** run automatically by the container entrypoint. Run them separately:

```bash
docker run --rm \
  -e DATABASE_URL="postgres://user:pass@host:5432/error_dashboard_production" \
  -e SECRET_KEY_BASE="dummy" \
  error-dashboard \
  bundle exec rails db:migrate
```

For Kubernetes deployments, migrations run as an ArgoCD PreSync job. See [Kubernetes Deployment](09-kubernetes.md).

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection URI |
| `SECRET_KEY_BASE` | Yes | Rails secret key for sessions/cookies |
| `API_BEARER_TOKEN` | Yes | Token for API authentication |
| `DASHBOARD_USERNAME` | No | Web UI username (default: `admin`) |
| `DASHBOARD_PASSWORD` | No | Web UI password (default: `changeme`) |
| `SLACK_WEBHOOK_URL` | No | Slack incoming webhook URL (enables notifications) |
| `SLACK_SIGNING_SECRET` | No | Slack app signing secret (for interactive actions) |
| `DASHBOARD_BASE_URL` | No | Public URL for dashboard links in Slack messages |
| `GIT_SHA` | No | Git commit SHA for source code links |
| `PORT` | No | Server port (default: `80`) |
| `RAILS_MAX_THREADS` | No | Puma thread count (default: `3`) |
| `JOB_CONCURRENCY` | No | Solid Queue worker concurrency (default: `1`) |

## Health Check

```bash
curl http://localhost:3000/health
# {"status":"ok"}
```

Returns `200` when the database is reachable, `503` otherwise. No authentication required. Used for Kubernetes liveness/readiness probes.

## First Error

Send a test error to verify the setup:

```bash
curl -X POST http://localhost:3000/api/v1/errors \
  -H "Authorization: Bearer your-api-token" \
  -H "Content-Type: application/json" \
  -d '{
    "error": {
      "error_type": "TestError",
      "message": "Hello from the error dashboard!",
      "severity": "info",
      "platform": "ruby",
      "occurred_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }
  }'
```

Then visit `/error_dashboard` to see it in the UI.
