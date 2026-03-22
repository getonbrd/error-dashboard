# Customization

The Error Dashboard is built on the `rails_error_dashboard` gem and can be customized through its configuration block and by overriding gem classes in initializers.

## Configuration

All configuration is in `config/initializers/rails_error_dashboard.rb`:

```ruby
RailsErrorDashboard.configure do |config|
  # Dashboard auth
  config.dashboard_username = ENV.fetch("DASHBOARD_USERNAME", "admin")
  config.dashboard_password = ENV.fetch("DASHBOARD_PASSWORD", "changeme")

  # Error capture
  config.enable_middleware = true
  config.enable_error_subscriber = true
  config.async_logging = true
  config.async_adapter = :solid_queue
  config.max_backtrace_lines = 100

  # Application identity
  config.application_name = "getonbrd"

  # Retention
  config.retention_days = 90

  # Source code links
  config.enable_source_code_integration = true
  config.git_repository_url = "https://github.com/getonbrd/getonbrd"
  config.git_sha = ENV["GIT_SHA"]
  config.source_code_context_lines = 10
  config.only_show_app_code_source = true

  # Slack
  config.enable_slack_notifications = ENV["SLACK_WEBHOOK_URL"].present?
  config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
  config.dashboard_base_url = ENV.fetch("DASHBOARD_BASE_URL", "https://error-dashboard.getonbrd.com")
  config.notification_cooldown_minutes = 15
end
```

## Overriding ErrorLog Methods

The gem's `ErrorLog` model can be extended via `class_eval`:

```ruby
RailsErrorDashboard::ErrorLog.class_eval do
  # The gem assumes a `user` association exists.
  # Override with a no-op if your app has no User model.
  def user
    nil
  end

  # Derive git_sha from app_version if not set directly.
  # Strips "sha-" prefix from image tags like "sha-abc1234".
  def git_sha
    super.presence || app_version&.delete_prefix("sha-")
  end
end
```

## Customizing Slack Notifications

Override `SlackPayloadBuilder` to change the notification format:

```ruby
RailsErrorDashboard::Services::SlackPayloadBuilder.class_eval do
  class << self
    def call(error_log)
      {
        blocks: [
          header_block(error_log),
          info_block(error_log),
          message_block(error_log),
          stacktrace_block(error_log),
          request_block(error_log),
          actions_block(error_log),
          context_block(error_log)
        ].compact
      }
    end

    def header_block(error_log)
      # Severity-based emoji
      emoji = case error_log.priority_level
              when 3.. then ":red_circle:"
              when 2    then ":large_orange_circle:"
              when 1    then ":yellow_circle:"
              else           ":white_circle:"
              end

      {
        type: "header",
        text: { type: "plain_text", text: "#{emoji} #{error_log.error_type}", emoji: true }
      }
    end

    def info_block(error_log)
      parts = []
      parts << "*#{error_log.occurrence_count}x*" if error_log.occurrence_count > 1
      parts << (error_log.user_id? ? ":bust_in_silhouette: User ##{error_log.user_id}" : ":ghost: Anonymous")
      parts << error_log.severity.to_s

      { type: "section", text: { type: "mrkdwn", text: parts.join(" · ") } }
    end

    def message_block(error_log)
      { type: "section", text: { type: "mrkdwn", text: "`#{error_log.message.truncate(500)}`" } }
    end

    def stacktrace_block(error_log)
      return nil if error_log.backtrace.blank?

      frame = Array(error_log.backtrace).find { |l| l.include?("app/") }
      return nil unless frame

      { type: "section", text: { type: "mrkdwn", text: frame.truncate(200) } }
    end

    def request_block(error_log)
      url = error_log.request_url
      return nil if url.blank? || !(url.start_with?("/") || url.start_with?("http"))

      { type: "section", text: { type: "mrkdwn", text: ":link: #{url}" } }
    end

    def actions_block(error_log)
      # Includes "View Source" link and "Resolve" danger button with confirmation
      # ...
    end

    def context_block(error_log)
      base_url = RailsErrorDashboard.configuration.dashboard_base_url
      {
        type: "context",
        elements: [{
          type: "mrkdwn",
          text: "<#{base_url}/error_dashboard/error_logs/#{error_log.id}|View in dashboard>"
        }]
      }
    end
  end
end
```

Each method returns a [Slack Block Kit](https://api.slack.com/block-kit) hash. Return `nil` to omit a block.

## Extension Points Summary

| What | How | Where |
|------|-----|-------|
| Error model behavior | `ErrorLog.class_eval` | Initializer |
| Slack notification format | `SlackPayloadBuilder.class_eval` | Initializer |
| Slack interactive actions | `SlackInteractionsController` | Controller |
| Dashboard auth | `config.dashboard_username/password` | Config block |
| Error capture behavior | `config.enable_middleware` | Config block |
| Retention policy | `config.retention_days` | Config block |
| Source code links | `config.git_repository_url` | Config block |
| Notification throttling | `config.notification_cooldown_minutes` | Config block |
