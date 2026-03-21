# Error Dashboard

Self-hosted error monitoring for [GetOnBrd](https://www.getonbrd.com), powered by [rails_error_dashboard](https://github.com/AnjanJ/rails_error_dashboard).

A standalone Rails 8 app that collects, aggregates, and displays application errors — replacing SaaS error tracking with a solution we fully own and control.

## Architecture

```
┌──────────────┐   POST /api/v1/errors   ┌──────────────────┐     ┌────────────┐
│  GetOnBrd    │ ───────────────────────► │  Error Dashboard │────►│  Postgres  │
│  Rails app   │     Bearer token auth    │  Rails 8 + gem   │     │  (CNPG)    │
└──────────────┘                          └──────────────────┘     └────────────┘
                                            │
                                            ├── /error_dashboard  (Web UI)
                                            ├── /api/v1/errors    (Ingestion API)
                                            └── /health           (Health check)
```

- **Web UI**: Browse, filter, resolve, and assign errors. Protected by HTTP Basic Auth.
- **Ingestion API**: Accepts error reports from external apps via Bearer token.
- **Async processing**: Solid Queue (backed by the same Postgres — no Redis needed).

## Stack

| Component | Technology |
|-----------|-----------|
| Runtime | Ruby 3.4, Rails 8.1 |
| Database | PostgreSQL 17 (CloudNativePG) |
| Job backend | Solid Queue |
| Error engine | [rails_error_dashboard](https://github.com/AnjanJ/rails_error_dashboard) |
| Deployment | Kubernetes (Hetzner), ArgoCD, Helm |
| CI | GitHub Actions → Docker Hub |

## API

### `POST /api/v1/errors`

Submit a single error report.

```bash
curl -X POST https://error-dashboard.getonbrd.com/api/v1/errors \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "error": {
      "error_type": "NoMethodError",
      "message": "undefined method `foo` for nil",
      "backtrace": ["app/models/user.rb:42:in `process`"],
      "severity": "error",
      "platform": "ruby",
      "source": "getonbrd",
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

### `POST /api/v1/errors/batch`

Submit multiple errors in one request.

```bash
curl -X POST https://error-dashboard.getonbrd.com/api/v1/errors/batch \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"errors": [{"error_type": "...", "message": "..."}, ...]}'
```

### `GET /health`

Returns `200 OK` with `{"status": "ok"}` when the app and database are healthy.

## Local development

```bash
# Prerequisites: Ruby 3.4, PostgreSQL

bin/setup
bin/rails db:migrate
bin/dev
```

The dashboard will be available at `http://localhost:3000/error_dashboard` with default credentials `admin` / `changeme`.

## Configuration

All configuration is via environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | — |
| `SECRET_KEY_BASE` | Rails secret key | — |
| `API_BEARER_TOKEN` | Token for the ingestion API | — |
| `DASHBOARD_USERNAME` | Dashboard HTTP Basic Auth user | `admin` |
| `DASHBOARD_PASSWORD` | Dashboard HTTP Basic Auth password | `changeme` |
| `RAILS_MAX_THREADS` | Puma thread count | `3` |
| `RAILS_LOG_LEVEL` | Log level | `info` |
| `PORT` | Server port | `80` |

## Deployment

This app is deployed to our Kubernetes cluster via ArgoCD. The Helm chart lives in the [k8s-cluster](https://github.com/getonbrd/k8s-cluster) repo under `applications/error-dashboard/`.

```bash
# Build and push image manually (CI does this on push to main)
docker build -t docker.io/getonbrd/error-dashboard:sha-$(git rev-parse --short HEAD) .
docker push docker.io/getonbrd/error-dashboard:sha-$(git rev-parse --short HEAD)
```

## License

This project is open source under the [MIT License](LICENSE).
