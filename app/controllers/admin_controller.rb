class AdminController < ActionController::Base
  http_basic_authenticate_with(
    name: ENV.fetch("DASHBOARD_USERNAME", "admin"),
    password: ENV.fetch("DASHBOARD_PASSWORD", "changeme")
  )
end
