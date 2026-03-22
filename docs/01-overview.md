# Error Dashboard — Overview

A self-hosted error monitoring dashboard for Ruby/Rails applications. Built as a standalone Rails 8 app powered by the [`rails_error_dashboard`](https://rubygems.org/gems/rails_error_dashboard) gem.

## Why Self-Hosted?

- Full ownership of error data
- No per-event pricing or vendor lock-in
- Custom Slack notifications with interactive actions
- Source code links to your private GitHub repos
- Deployed alongside your existing Kubernetes infrastructure

## Architecture

```
┌─────────────────────┐
│   Rails App          │
│  (ErrorReporter +    │──── POST /api/v1/errors ────┐
│   Sidekiq Worker)    │                              │
└─────────────────────┘                              ▼
                                          ┌──────────────────────┐
                                          │  Error Dashboard     │
                                          │  (Rails 8)           │
                                          │                      │
                                          │  ┌────────────────┐  │
                                          │  │ Web UI (Basic   │  │
                                          │  │ Auth)           │  │
                                          │  ├────────────────┤  │
                                          │  │ REST API        │  │
                                          │  │ (Bearer Token)  │  │
                                          │  ├────────────────┤  │
                                          │  │ Solid Queue     │  │
                                          │  │ (async jobs)    │  │
                                          │  └────────────────┘  │
                                          │          │           │
                                          │          ▼           │
                                          │  ┌────────────────┐  │
                                          │  │ PostgreSQL      │  │
                                          │  └────────────────┘  │
                                          └──────────┬───────────┘
                                                     │
                                                     ▼
                                          ┌──────────────────────┐
                                          │  Slack               │
                                          │  (Notifications +    │
                                          │   Resolve Button)    │
                                          └──────────────────────┘
```

## Core Features

| Feature | Description |
|---------|-------------|
| **Web UI** | Browse, search, and resolve errors (HTTP Basic Auth) |
| **REST API** | Ingest errors via POST, query via GET (Bearer Token) |
| **Slack Notifications** | Rich error alerts with interactive Resolve button |
| **Source Code Links** | Click backtrace frames to view source on GitHub |
| **Error Deduplication** | Groups identical errors by hash, tracks occurrence counts |
| **Retention Cleanup** | Automatic deletion of old errors (configurable, default 90 days) |
| **Async Processing** | Solid Queue for background jobs — no Redis required |

## Key Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/error_dashboard` | Web UI |
| `/api/v1/errors` | Error ingest & query API |
| `/api/v1/errors/batch` | Batch error ingest |
| `/health` | Health check (database connectivity) |
| `/slack/interactions` | Slack interactive callbacks |

## Pages

1. [Overview](01-overview.md) — You are here
2. [Getting Started](02-getting-started.md) — Deploy and set up
3. [Client Integration Guide](03-client-integration.md) — Send errors from your Rails app
4. [API Reference](04-api-reference.md) — Endpoint details and payload schema
5. [Slack Integration](05-slack-integration.md) — Notifications and interactive actions
6. [Source Code Integration](06-source-code-integration.md) — GitHub links from backtraces
7. [Error Deduplication & Grouping](07-deduplication.md) — How errors are grouped
8. [Retention & Cleanup](08-retention.md) — Automatic error cleanup
9. [Customization](10-customization.md) — Extending the dashboard
