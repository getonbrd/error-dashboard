RailsErrorDashboard.configure do |config|
  config.dashboard_username = ENV.fetch("DASHBOARD_USERNAME", "admin")
  config.dashboard_password = ENV.fetch("DASHBOARD_PASSWORD", "changeme")

  config.enable_middleware = true
  config.enable_error_subscriber = true

  config.async_logging = true
  config.async_adapter = :solid_queue

  config.retention_days = 90
  config.max_backtrace_lines = 100

  config.application_name = "getonbrd"

  config.enable_source_code_integration = true
  config.git_repository_url = "https://github.com/getonbrd/getonbrd"
  config.git_sha = ENV["GIT_SHA"]
  config.source_code_context_lines = 10
  config.only_show_app_code_source = true

  config.enable_slack_notifications = ENV["SLACK_WEBHOOK_URL"].present?
  config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
  config.dashboard_base_url = ENV.fetch("DASHBOARD_BASE_URL", "https://error-dashboard.getonbrd.com")
  config.notification_cooldown_minutes = 15
end

# The gem's Slack payload builder calls error_log.user, which assumes a User
# model and belongs_to association. Since this is a standalone app with no User
# model, we add a no-op method so it returns nil gracefully.
Rails.application.config.after_initialize do
  next unless defined?(RailsErrorDashboard::ErrorLog)

  RailsErrorDashboard::ErrorLog.class_eval do
    def user
      nil
    end

    # Use app_version (e.g. "sha-abc1234") as git_sha for "View Source" links
    # when git_sha isn't set directly by the gem.
    def git_sha
      super.presence || app_version&.delete_prefix("sha-")
    end
  end

  # Remove "Error ID:" context block from Slack notifications
  # and add "Resolve" button
  RailsErrorDashboard::Services::SlackPayloadBuilder.class_eval do
    class << self
      def call(error_log)
        {
          text: "#{error_log.error_type}: #{error_log.message&.truncate(100)}",
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

      def header_block(error_log = nil)
        severity_emoji = severity_circle(error_log)
        {
          type: "header",
          text: {
            type: "plain_text",
            text: "#{severity_emoji} #{error_log&.error_type || 'Error'}",
            emoji: true
          }
        }
      end

      # Occurrences, user status, severity in one compact line
      def info_block(error_log)
        parts = []
        parts << ":repeat: *#{error_log.occurrence_count}x*" if error_log.occurrence_count > 1
        parts << (error_log.user_id.present? ? ":bust_in_silhouette: User ##{error_log.user_id}" : ":ghost: Anonymous")
        {
          type: "context",
          elements: [{ type: "mrkdwn", text: parts.join("  ·  ") }]
        }
      end

      # First line of the stacktrace
      def stacktrace_block(error_log)
        bt = error_log.backtrace
        if bt.is_a?(String)
          bt = (JSON.parse(bt) rescue bt.split("\n"))
        end
        bt = Array(bt)
        first_line = bt.find { |l| l.include?("app/") } || bt.first
        return nil unless first_line.present?

        {
          type: "section",
          text: { type: "mrkdwn", text: "*Stacktrace:*\n`#{first_line.truncate(200)}`" }
        }
      end

      def message_block(error_log)
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: "```#{RailsErrorDashboard::Services::NotificationHelpers.truncate_message(error_log.message)}```"
          }
        }
      end

      def fields_block(_error_log)
        nil
      end

      # Hide the gem's user block — we show user info in info_block
      def user_block(_error_log)
        nil
      end

      # Hide request URL when it's just the source name (no real URL)
      def request_block(error_log)
        url = error_log.request_url
        return nil if url.blank? || !url.start_with?("/", "http")

        {
          type: "section",
          text: { type: "mrkdwn", text: "*Request:* `#{RailsErrorDashboard::Services::NotificationHelpers.truncate_message(url, 200)}`" }
        }
      end

      def severity_circle(error_log)
        case error_log.priority_level.to_i
        when 3..Float::INFINITY then ":red_circle:"
        when 2 then ":large_orange_circle:"
        when 1 then ":yellow_circle:"
        else ":white_circle:"
        end
      end

      def context_block(error_log)
        url = RailsErrorDashboard::Services::NotificationHelpers.dashboard_url(error_log)
        {
          type: "context",
          elements: [
            { type: "mrkdwn", text: "<#{url}>" }
          ]
        }
      end

      alias_method :original_actions_block, :actions_block

      def actions_block(error_log)
        block = original_actions_block(error_log)
        block[:elements] << {
          type: "button",
          text: {
            type: "plain_text",
            text: "Resolve",
            emoji: true
          },
          action_id: "resolve_error_#{error_log.id}",
          style: "danger",
          confirm: {
            title: { type: "plain_text", text: "Resolve error?" },
            text: { type: "mrkdwn", text: "Mark *#{error_log.error_type}* as resolved?" },
            confirm: { type: "plain_text", text: "Resolve" },
            deny: { type: "plain_text", text: "Cancel" }
          }
        }
        block
      end
    end
  end
end
