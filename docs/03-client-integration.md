# Client Integration Guide

This guide covers integrating a Rails application with the Error Dashboard. The examples are based on GetOnBrd's production integration, which uses a wrapper module (`ErrorReporter`), async delivery via Sidekiq, and automatic capture via Rack middleware.

## Architecture

```
Exception occurs
       │
       ▼
ErrorReporter.notify(error, metadata:, severity:, context:)
       │
       ├──▶ Bugsnag.notify()              [synchronous, always]
       │
       └──▶ ErrorDashboardWorker           [async via Sidekiq]
               .perform_async(payload)
                       │
                       ▼
              HTTP POST /api/v1/errors     [with Bearer token]
```

Errors are sent asynchronously through a Sidekiq worker to avoid impacting request latency.

## 1. ErrorReporter Module

The central module for all error reporting. Handles dual-sending to both Bugsnag and the Error Dashboard.

```ruby
# app/services/error_reporter.rb
module ErrorReporter
  module_function

  def notify(error, metadata: {}, severity: nil, context: {})
    notify_bugsnag(error, severity: severity, context: context)
    notify_dashboard(error, metadata: metadata, severity: severity, context: context)
  rescue StandardError => e
    Rails.logger.error("[ErrorReporter] Failed to report error: #{e.message}")
  end

  def notify_dashboard(error, metadata: {}, severity: nil, context: {})
    return unless enabled?

    ErrorDashboardWorker.perform_async(
      error.class.name,
      error.message,
      error.backtrace&.first(100),
      {
        severity: severity || "error",
        platform: "ruby",
        app_version: app_version,
        user_id: context[:user_id] || Thread.current[:error_dashboard_user_id],
        request_url: Thread.current[:error_dashboard_request_url],
        ip_address: Thread.current[:error_dashboard_ip_address],
        user_agent: Thread.current[:error_dashboard_user_agent],
        occurred_at: Time.current.iso8601,
        metadata: metadata
      }
    )
  end

  def enabled?
    ENV["ERROR_DASHBOARD_ENABLED"] == "true" && ENV["ERROR_DASHBOARD_URL"].present?
  end

  def app_version
    ENV["IMAGE_TAG"] ||
      (ENV["HEROKU_SLUG_COMMIT"] && "sha-#{ENV['HEROKU_SLUG_COMMIT'][0..6]}") ||
      "unknown"
  end

  # Thread-local accessors for request context
  def set_request_context(url:, ip:, user_agent:)
    Thread.current[:error_dashboard_request_url] = url
    Thread.current[:error_dashboard_ip_address] = ip
    Thread.current[:error_dashboard_user_agent] = user_agent
  end

  def clear_request_context
    Thread.current[:error_dashboard_request_url] = nil
    Thread.current[:error_dashboard_ip_address] = nil
    Thread.current[:error_dashboard_user_agent] = nil
  end
end
```

## 2. ErrorDashboardWorker (Async HTTP Delivery)

Sends errors to the dashboard API via HTTP POST in a background job.

```ruby
# app/workers/error_dashboard_worker.rb
class ErrorDashboardWorker
  include Sidekiq::Worker

  sidekiq_options queue: :low_priority, retry: 3

  def perform(error_type, message, backtrace, options = {})
    uri = URI("#{ENV['ERROR_DASHBOARD_URL']}/api/v1/errors")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 5

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{ENV['ERROR_DASHBOARD_API_TOKEN']}"
    request.body = {
      error: {
        error_type: error_type,
        message: message,
        backtrace: backtrace,
        **options.symbolize_keys
      }
    }.to_json

    response = http.request(request)
    raise "Error Dashboard returned #{response.code}" if response.code.to_i >= 400
  end
end
```

### Why Sidekiq?

- Errors are delivered asynchronously — no impact on request latency
- Automatic retries (3 attempts) with exponential backoff on failure
- Uses `low_priority` queue so error reporting never competes with critical jobs
- 5-second timeout prevents hanging connections from blocking workers

## 3. Rack Middleware (Automatic Controller Error Capture)

Captures unhandled exceptions at the Rack level and stores request context for ErrorReporter.

```ruby
# app/middleware/error_dashboard_middleware.rb
class ErrorDashboardMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    # Store request context in thread locals
    request = ActionDispatch::Request.new(env)
    ErrorReporter.set_request_context(
      url: request.original_url,
      ip: (request.remote_ip rescue nil),
      user_agent: request.user_agent
    )

    @app.call(env)
  rescue Exception => e
    ErrorReporter.notify_dashboard(e, metadata: {
      http_method: request.method,
      controller: env["action_dispatch.request.path_parameters"]&.dig(:controller),
      action: env["action_dispatch.request.path_parameters"]&.dig(:action)
    })
    raise
  ensure
    ErrorReporter.clear_request_context
  end
end
```

Register in `config/application.rb`:

```ruby
require_relative "../app/middleware/error_dashboard_middleware"
config.middleware.use ErrorDashboardMiddleware
```

The middleware:
- Stores request URL, IP, and user agent in thread locals (available to ErrorReporter downstream)
- Catches **all** unhandled exceptions and reports them before re-raising
- Cleans up thread locals in the `ensure` block

## 4. Sidekiq Error Handler (Automatic Job Error Capture)

Add a custom error handler to capture unhandled Sidekiq job failures:

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.error_handlers << proc { |e, context|
    ErrorReporter.notify_dashboard(e, metadata: context) if ErrorReporter.enabled?
  }
end
```

This catches errors from **any** Sidekiq job without needing explicit `rescue` blocks.

## 5. Environment Variables

Set these in your application's environment:

| Variable | Description |
|----------|-------------|
| `ERROR_DASHBOARD_ENABLED` | Must be `"true"` to enable sending |
| `ERROR_DASHBOARD_URL` | Base URL of the dashboard (e.g., `https://error-dashboard.getonbrd.com`) |
| `ERROR_DASHBOARD_API_TOKEN` | Bearer token (must match `API_BEARER_TOKEN` on the dashboard) |
| `IMAGE_TAG` | Docker image tag for `app_version` (Kubernetes) |
| `HEROKU_SLUG_COMMIT` | Git SHA for `app_version` (Heroku) |

## 6. Usage Examples

### Explicit Error Reporting

```ruby
# Basic
ErrorReporter.notify(error)

# With metadata and severity
ErrorReporter.notify(error,
  metadata: { company_id: company.id, action: "sync" },
  severity: "warning"
)

# With user context
ErrorReporter.notify(error,
  context: { user_id: current_user.id }
)
```

### In a Service

```ruby
class PaymentService
  def charge(subscription)
    # ... payment logic ...
  rescue Stripe::CardError => e
    ErrorReporter.notify(e,
      metadata: { subscription_id: subscription.id },
      severity: "warning"
    )
    raise
  rescue StandardError => e
    ErrorReporter.notify(e,
      metadata: { subscription_id: subscription.id },
      severity: "error"
    )
    raise
  end
end
```

### In a Controller

```ruby
class WebhooksController < ApplicationController
  def stripe
    # ... handle webhook ...
  rescue JSON::ParserError => e
    ErrorReporter.notify(e, metadata: { body: request.raw_post.truncate(500) })
    head :bad_request
  end
end
```

## 7. Migrating from Bugsnag

### Phase 1: Dual-Sending

Keep Bugsnag active and send errors to both systems simultaneously. The `ErrorReporter.notify` method handles this — both `notify_bugsnag` and `notify_dashboard` are called on every error.

### Phase 2: Replace Direct Bugsnag Calls

Find and replace all direct `Bugsnag.notify` calls with `ErrorReporter.notify`:

```ruby
# Before
Bugsnag.notify(error)
Bugsnag.notify(error) do |report|
  report.severity = "warning"
  report.add_tab(:context, { user_id: user.id })
end

# After
ErrorReporter.notify(error)
ErrorReporter.notify(error,
  severity: "warning",
  context: { user_id: user.id }
)
```

### Phase 3: Validate

Run both systems in parallel. Compare error counts and types between Bugsnag and the Error Dashboard to verify nothing is missing.

### Phase 4: Remove Bugsnag

Once confident, remove the Bugsnag gem, delete `notify_bugsnag` from ErrorReporter, and remove the Bugsnag initializer.
