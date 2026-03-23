# Protect the jobs dashboard with the same credentials as the error dashboard
MissionControl::Jobs.base_controller_class = "AdminController"
