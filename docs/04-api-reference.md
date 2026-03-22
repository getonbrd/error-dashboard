# API Reference

All API endpoints are under `/api/v1/` and require Bearer token authentication.

## Authentication

Include the token in the `Authorization` header:

```
Authorization: Bearer <API_BEARER_TOKEN>
```

The token is validated against the `API_BEARER_TOKEN` environment variable using constant-time comparison (`ActiveSupport::SecurityUtils.secure_compare`).

**Unauthorized response** (401):

```json
{ "error": "Unauthorized" }
```

## POST /api/v1/errors

Create a single error log entry.

### Request

```bash
curl -X POST https://error-dashboard.example.com/api/v1/errors \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "error": {
      "error_type": "NoMethodError",
      "message": "undefined method `name` for nil:NilClass",
      "severity": "error",
      "platform": "ruby",
      "source": "rack_middleware",
      "app_version": "sha-abc1234",
      "user_id": 42,
      "request_url": "https://app.example.com/dashboard",
      "ip_address": "203.0.113.1",
      "user_agent": "Mozilla/5.0 ...",
      "occurred_at": "2026-03-22T10:30:00Z",
      "backtrace": [
        "app/controllers/dashboard_controller.rb:15:in `show`",
        "app/middleware/auth.rb:8:in `call`"
      ],
      "metadata": {
        "company_id": 123,
        "request_id": "abc-def-ghi"
      }
    }
  }'
```

### Payload Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `error_type` | string | Yes | Exception class name (e.g., `NoMethodError`) |
| `message` | string | Yes | Error message |
| `severity` | string | No | `info`, `warning`, `error` (default: `error`) |
| `platform` | string | No | Runtime platform (e.g., `ruby`) |
| `source` | string | No | Where the error was captured (e.g., `rack_middleware`, `sidekiq`) |
| `app_version` | string | No | Release version or git SHA (e.g., `sha-abc1234`) |
| `user_id` | integer | No | Application user identifier |
| `request_url` | string | No | URL of the request that triggered the error |
| `ip_address` | string | No | Client IP address |
| `user_agent` | string | No | Client user agent string |
| `occurred_at` | datetime | No | When the error occurred (ISO 8601, defaults to now) |
| `backtrace` | array | No | Stack trace as array of strings |
| `metadata` | object | No | Arbitrary key-value context data |

### Response (201)

```json
{ "status": "accepted" }
```

## POST /api/v1/errors/batch

Create multiple error log entries in a single request.

### Request

```bash
curl -X POST https://error-dashboard.example.com/api/v1/errors/batch \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "errors": [
      {
        "error_type": "TimeoutError",
        "message": "Connection timed out",
        "platform": "ruby",
        "occurred_at": "2026-03-22T10:30:00Z"
      },
      {
        "error_type": "Redis::ConnectionError",
        "message": "Could not connect to Redis",
        "platform": "ruby",
        "occurred_at": "2026-03-22T10:30:01Z"
      }
    ]
  }'
```

### Response (201)

```json
{ "logged": 2, "total": 2 }
```

## GET /api/v1/errors

List errors with optional filters and pagination.

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `error_type` | string | Filter by exception class |
| `platform` | string | Filter by platform |
| `resolved` | boolean | Filter by resolution status |
| `priority_level` | integer | Filter by priority (0-3) |
| `page` | integer | Page number (default: 1) |
| `per_page` | integer | Results per page (default: 25) |

### Request

```bash
curl "https://error-dashboard.example.com/api/v1/errors?resolved=false&page=1&per_page=10" \
  -H "Authorization: Bearer <token>"
```

### Response (200)

```json
{
  "errors": [
    {
      "id": 42,
      "error_type": "NoMethodError",
      "message": "undefined method `name` for nil:NilClass",
      "platform": "ruby",
      "occurred_at": "2026-03-22T10:30:00Z",
      "occurrence_count": 5,
      "first_seen_at": "2026-03-20T08:00:00Z",
      "last_seen_at": "2026-03-22T10:30:00Z",
      "resolved": false,
      "priority_level": 2,
      "status": "new",
      "controller_name": "DashboardController",
      "action_name": "show",
      "app_version": "sha-abc1234",
      "user_id": 42,
      "request_url": "https://app.example.com/dashboard",
      "created_at": "2026-03-20T08:00:00Z",
      "updated_at": "2026-03-22T10:30:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "per_page": 10,
    "total": 42
  }
}
```

Note: List responses omit `backtrace`, `ip_address`, `user_agent`, `request_params`, and `git_sha` for performance.

## GET /api/v1/errors/:id

Get full details of a single error.

### Request

```bash
curl "https://error-dashboard.example.com/api/v1/errors/42" \
  -H "Authorization: Bearer <token>"
```

### Response (200)

Returns the full error record including `backtrace`, `ip_address`, `user_agent`, `request_params`, and `git_sha`.

### Not Found (404)

```json
{ "error": "Not found" }
```

## GET /health

Health check endpoint. **No authentication required.**

### Response (200)

```json
{ "status": "ok" }
```

### Response (503)

```json
{ "status": "error", "message": "PG::ConnectionBad: could not connect to server" }
```

## Error Responses

| Status | Meaning |
|--------|---------|
| 401 | Missing or invalid Bearer token |
| 404 | Resource not found |
| 422 | Invalid payload (missing required fields) |
| 503 | Database unavailable (health check only) |
