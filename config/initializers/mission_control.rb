# Protect the jobs dashboard with the same credentials as the error dashboard
MissionControl::Jobs.base_controller_class = "MissionControl::Jobs::ApplicationController"
MissionControl::Jobs::ApplicationController.class_eval do
  http_basic_authenticate_with(
    name: ENV.fetch("DASHBOARD_USERNAME", "admin"),
    password: ENV.fetch("DASHBOARD_PASSWORD", "changeme")
  )
end
