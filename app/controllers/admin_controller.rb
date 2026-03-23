class AdminController < ActionController::Base
  before_action :authenticate

  private

  def authenticate
    authenticate_or_request_with_http_basic("Error Dashboard") do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username, ENV.fetch("DASHBOARD_USERNAME", "admin")) &
        ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("DASHBOARD_PASSWORD", "changeme"))
    end
  end
end
