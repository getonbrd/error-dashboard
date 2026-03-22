# Retention & Cleanup

The Error Dashboard automatically deletes old error records to keep the database size manageable.

## Configuration

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.retention_days = 90  # delete errors older than 90 days
end
```

## RetentionCleanupJob

The `RailsErrorDashboard::RetentionCleanupJob` runs on a recurring schedule via Solid Queue:

```yaml
# config/recurring.yml
production:
  retention_cleanup:
    class: RailsErrorDashboard::RetentionCleanupJob
    schedule: at 4am every day
```

**Behavior:**
- Deletes `ErrorLog` records where `occurred_at` is older than `retention_days`
- Runs daily at 4:00 AM (configured in `recurring.yml`)

## Solid Queue Cleanup

Solid Queue's own finished jobs are also cleaned up on a recurring schedule:

```yaml
production:
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
    schedule: every hour at minute 12
```

This clears completed job records hourly in batches (with 0.3s sleep between batches to avoid lock contention).

## Manual Cleanup

To manually trigger cleanup:

```bash
# Delete errors older than the configured retention period
bundle exec rails runner "RailsErrorDashboard::RetentionCleanupJob.perform_now"

# Or via Rails console
RailsErrorDashboard::RetentionCleanupJob.perform_now
```

## Database Considerations

Both the application data and Solid Queue tables share the same PostgreSQL database (configured via `DATABASE_URL`). The retention job keeps the `error_logs` table from growing unbounded, and the Solid Queue cleanup keeps the `solid_queue_*` tables clean.
