# Use Mission Control's built-in HTTP Basic Auth
MissionControl::Jobs.http_basic_auth_enabled = true
MissionControl::Jobs.http_basic_auth_user = ENV.fetch("DASHBOARD_USERNAME", "admin")
MissionControl::Jobs.http_basic_auth_password = ENV.fetch("DASHBOARD_PASSWORD", "changeme")
