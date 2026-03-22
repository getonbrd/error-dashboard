# Protect the jobs dashboard with the same credentials as the error dashboard
Rails.application.config.after_initialize do
  MissionControl::Jobs::ApplicationController.http_basic_authenticate_with(
    name: ENV.fetch("DASHBOARD_USERNAME", "admin"),
    password: ENV.fetch("DASHBOARD_PASSWORD", "changeme")
  )
end
