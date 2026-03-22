# Error Dashboard

A self-hosted error monitoring app powered by [rails_error_dashboard](https://github.com/AnjanJ/rails_error_dashboard).

A standalone Rails 8 app that collects, aggregates, and displays application errors — replacing SaaS error tracking with a solution you fully own and control.

## Architecture

```
┌──────────────┐   POST /api/v1/errors   ┌──────────────────┐     ┌────────────┐
│  Your app    │ ───────────────────────► │  Error Dashboard │────►│  Postgres  │
│              │     Bearer token auth    │  Rails 8 + gem   │     │            │
└──────────────┘                          └──────────────────┘     └────────────┘
                                            │
                                            ├── /error_dashboard  (Web UI)
                                            ├── /api/v1/errors    (REST API)
                                            └── /health           (Health check)
```

- **Web UI**: Browse, filter, resolve, and assign errors. Protected by HTTP Basic Auth.
- **REST API**: Ingest and read errors via Bearer token auth.
- **Slack**: Notifications with severity indicators, occurrence counts, and interactive Resolve button.
- **Source code**: "View Source" links to the exact file/line on GitHub.
- **Async processing**: Solid Queue (backed by the same Postgres — no Redis needed).
- **Deduplication**: Errors are grouped by hash — recurring errors increment the count, not create duplicates.
- **Retention**: Automatic cleanup of errors older than the configured retention period (default 90 days).

## Stack

| Component | Technology |
|-----------|-----------|
| Runtime | Ruby 3.4, Rails 8.1 |
| Database | PostgreSQL |
| Job backend | Solid Queue |
| Error engine | [rails_error_dashboard](https://github.com/AnjanJ/rails_error_dashboard) |

## API

All endpoints require `Authorization: Bearer <token>`.

### Ingest

#### `POST /api/v1/errors`

Submit a single error report.

```bash
curl -X POST https://your-dashboard.example.com/api/v1/errors \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "error": {
      "error_type": "NoMethodError",
      "message": "undefined method `foo` for nil",
      "backtrace": ["app/models/user.rb:42:in `process`"],
      "severity": "error",
      "platform": "ruby",
      "source": "my-app",
      "app_version": "sha-abc123",
      "user_id": "42",
      "request_url": "/jobs/123",
      "ip_address": "1.2.3.4",
      "user_agent": "Mozilla/5.0",
      "metadata": {"controller": "jobs", "action": "show"},
      "occurred_at": "2026-03-21T12:00:00Z"
    }
  }'
```

#### `POST /api/v1/errors/batch`

Submit multiple errors in one request.

```bash
curl -X POST https://your-dashboard.example.com/api/v1/errors/batch \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"errors": [{"error_type": "...", "message": "..."}, ...]}'
```

### Read

#### `GET /api/v1/errors`

List errors (paginated). Supports filters: `error_type`, `platform`, `resolved`, `priority_level`, `page`, `per_page`.

```bash
curl https://your-dashboard.example.com/api/v1/errors?error_type=NoMethodError&page=1 \
  -H "Authorization: Bearer <token>"
```

#### `GET /api/v1/errors/:id`

Error detail with backtrace, request params, and git SHA.

### `GET /health`

Returns `200 OK` with `{"status": "ok"}` when the app and database are healthy. No auth required.

## Slack Integration

Error notifications are sent to Slack with:
- Severity indicator (red/orange/yellow/white circle)
- Error type as the header
- Occurrence count for recurring errors
- First app stacktrace line
- Authenticated user or anonymous indicator
- Request URL (when available)
- **Resolve** button with confirmation dialog
- Link to the error in the dashboard

Configure via `SLACK_WEBHOOK_URL` and `SLACK_SIGNING_SECRET` env vars. Interactivity must be enabled in your Slack app settings with the Request URL pointing to `/slack/interactions`.

## Source Code Integration

Backtrace frames link to the exact file and line on GitHub. Configure `git_repository_url` in the initializer. The git SHA is derived from the `app_version` field sent with each error (e.g. `sha-abc1234`).

## Setup

### Local development

```bash
# Prerequisites: Ruby 3.4, PostgreSQL

bin/setup
bin/rails db:migrate
bin/dev
```

The dashboard will be available at `http://localhost:3000/error_dashboard` with default credentials `admin` / `changeme`.

### Docker

```bash
docker build -t error-dashboard .
docker run -d -p 80:80 \
  -e DATABASE_URL="postgres://user:pass@host/dbname" \
  -e SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  -e API_BEARER_TOKEN="$(openssl rand -hex 32)" \
  -e DASHBOARD_USERNAME="admin" \
  -e DASHBOARD_PASSWORD="your-secure-password" \
  error-dashboard
```

### Kubernetes

Deploy with any Kubernetes setup. The app needs:

- A PostgreSQL instance (for errors + Solid Queue)
- The environment variables listed below
- A single pod running the Rails server

## Configuration

All configuration is via environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | — |
| `SECRET_KEY_BASE` | Rails secret key | — |
| `API_BEARER_TOKEN` | Token for the ingestion API | — |
| `DASHBOARD_USERNAME` | Dashboard HTTP Basic Auth user | `admin` |
| `DASHBOARD_PASSWORD` | Dashboard HTTP Basic Auth password | `changeme` |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL (enables notifications) | — |
| `SLACK_SIGNING_SECRET` | Slack app signing secret (for interactive buttons) | — |
| `RAILS_MAX_THREADS` | Puma thread count | `3` |
| `RAILS_LOG_LEVEL` | Log level | `info` |
| `PORT` | Server port | `80` |

## License

This project is open source under the [MIT License](LICENSE).
