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
end
