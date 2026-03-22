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

  config.enable_slack_notifications = ENV["SLACK_WEBHOOK_URL"].present?
  config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
  config.dashboard_base_url = ENV.fetch("DASHBOARD_BASE_URL", "https://error-dashboard.getonbrd.com")
  config.notification_cooldown_minutes = 15
end
