# Error Deduplication & Grouping

The Error Dashboard deduplicates errors so repeated occurrences of the same error are tracked as a single entry with an occurrence count, rather than creating a new record for each one.

## How error_hash Works

Each error is assigned an `error_hash` — a fingerprint computed from:

- **error_type** — The exception class name (e.g., `NoMethodError`)
- **message** — The error message (normalized)
- **backtrace signature** — A hash of the relevant stack frames

When a new error arrives, the dashboard checks for an existing error with the same `error_hash`:

| Scenario | Action |
|----------|--------|
| No match | Creates a new `ErrorLog` record |
| Match found | Increments `occurrence_count`, updates `last_seen_at` |

## Tracked Fields

| Field | On First Occurrence | On Duplicate |
|-------|-------------------|--------------|
| `error_hash` | Set (indexed) | Used for lookup |
| `occurrence_count` | `1` | Incremented |
| `first_seen_at` | Set to current time | Never changes |
| `last_seen_at` | Set to current time | Updated to current time |

This means the dashboard shows **unique errors**, not individual events. An error that occurs 1,000 times appears as one row with `occurrence_count: 1000`.

## Similarity Scores

In addition to exact deduplication via `error_hash`, the gem computes a `similarity_score` between errors using their `backtrace_signature`. This helps identify errors that are related but not identical — for example, the same bug triggered from different code paths.

Both `error_hash` and `backtrace_signature` are indexed for fast lookups.

## Implications

### Resolving a Deduplicated Error

When you resolve an error, you're resolving all past and future occurrences with that hash. If the same error recurs after resolution, the gem creates a new record (or reopens the existing one, depending on configuration).

### Slack Notifications

Slack notifications respect the `notification_cooldown_minutes` setting. Even if an error's occurrence count keeps climbing, Slack won't be notified more than once per cooldown window.

### Retention

When retention cleanup runs, it deletes errors based on `occurred_at`. A deduplicated error with recent occurrences (`last_seen_at` within the retention window) is kept even if `first_seen_at` is older than the retention period.
