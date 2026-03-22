# Error Dashboard

A self-hosted error monitoring app powered by [rails_error_dashboard](https://github.com/AnjanJ/rails_error_dashboard).

A standalone Rails 8 app that collects, aggregates, and displays application errors — replacing SaaS error tracking with a solution you fully own and control.

## Architecture

```
┌──────────────┐   POST /api/v1/errors    ┌──────────────────┐     ┌────────────┐
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

## Documentation

For detailed guides on every feature, see the [docs/](docs/) folder:

1. [Overview](docs/01-overview.md) — Architecture and feature summary
2. [Getting Started](docs/02-getting-started.md) — Deploy and set up
3. [Client Integration Guide](docs/03-client-integration.md) — Send errors from your Rails app
4. [API Reference](docs/04-api-reference.md) — Endpoint details and payload schema
5. [Slack Integration](docs/05-slack-integration.md) — Notifications and interactive actions
6. [Source Code Integration](docs/06-source-code-integration.md) — GitHub links from backtraces
7. [Error Deduplication & Grouping](docs/07-deduplication.md) — How errors are grouped
8. [Retention & Cleanup](docs/08-retention.md) — Automatic error cleanup
9. [Customization](docs/10-customization.md) — Extending the dashboard

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

## Client Integration

To send errors from your Rails app to the dashboard, add these three files and configure the environment variables.

### 1. Rack Middleware (automatic capture)

Catches all unhandled exceptions at the Rack level — controllers, middleware, etc.

```ruby
# app/middleware/error_dashboard_middleware.rb
class ErrorDashboardMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    Thread.current[:error_dashboard_request_url] = request.original_url
    Thread.current[:error_dashboard_ip_address] = safe_remote_ip(request)
    Thread.current[:error_dashboard_user_agent] = request.user_agent

    @app.call(env)
  rescue Exception => e # rubocop:disable Lint/RescueException
    notify(e, request, env)
    raise
  ensure
    Thread.current[:error_dashboard_request_url] = nil
    Thread.current[:error_dashboard_ip_address] = nil
    Thread.current[:error_dashboard_user_agent] = nil
  end

  private def notify(error, request, env)
    return unless ENV["ERROR_DASHBOARD_ENABLED"] == "true"

    ErrorDashboardWorker.perform_async(
      "error_type" => error.class.name,
      "message" => error.message,
      "backtrace" => Array(error.backtrace).first(50),
      "severity" => "error",
      "source" => "my-app",
      "platform" => "ruby",
      "app_version" => ENV["IMAGE_TAG"] || ENV["HEROKU_SLUG_COMMIT"]&.slice(0, 7)&.then { "sha-#{_1}" } || "unknown",
      "request_url" => request.original_url,
      "ip_address" => safe_remote_ip(request),
      "user_agent" => request.user_agent,
      "metadata" => {
        "http_method" => request.method,
        "controller" => env["action_dispatch.request.path_parameters"]&.dig(:controller),
        "action" => env["action_dispatch.request.path_parameters"]&.dig(:action)
      }
    )
  rescue StandardError => e
    Rails.logger.error("[ErrorDashboardMiddleware] Failed: #{e.message}")
  end

  private def safe_remote_ip(request)
    request.remote_ip
  rescue ActionDispatch::RemoteIp::IpSpoofAttackError
    nil
  end
end
```

Register it in `config/application.rb`:

```ruby
require_relative "../app/middleware/error_dashboard_middleware"
config.middleware.use ErrorDashboardMiddleware
```

### 2. Sidekiq Error Handler (background jobs)

Add to your Sidekiq initializer to capture unhandled job errors:

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.error_handlers << proc { |e, context|
    if ENV["ERROR_DASHBOARD_ENABLED"] == "true"
      ErrorDashboardWorker.perform_async(
        "error_type" => e.class.name,
        "message" => e.message,
        "backtrace" => Array(e.backtrace).first(50),
        "severity" => "error",
        "source" => "my-app",
        "platform" => "ruby",
        "metadata" => context.transform_keys(&:to_s)
      )
    end
  }
end
```

### 3. Background Worker

Sends errors asynchronously to avoid blocking request threads:

```ruby
# app/workers/error_dashboard_worker.rb
class ErrorDashboardWorker
  include Sidekiq::Worker
  sidekiq_options queue: :low_priority, retry: 3

  def perform(error_params)
    uri = URI("#{ENV['ERROR_DASHBOARD_URL']}/api/v1/errors")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 5

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{ENV['ERROR_DASHBOARD_API_TOKEN']}"
    request.body = { error: error_params }.to_json

    response = http.request(request)
    raise "Error Dashboard API returned #{response.code}" unless response.code.to_i < 400
  end
end
```

### Client Environment Variables

| Variable | Description |
|----------|-------------|
| `ERROR_DASHBOARD_ENABLED` | Set to `"true"` to enable |
| `ERROR_DASHBOARD_URL` | Dashboard base URL (e.g. `https://errors.example.com`) |
| `ERROR_DASHBOARD_API_TOKEN` | Bearer token matching the dashboard's `API_BEARER_TOKEN` |

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
