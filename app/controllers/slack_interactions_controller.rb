require "net/http"

# Handles Slack interactive component callbacks (button clicks, etc.)
# Slack sends a POST with a JSON payload when a user clicks a button.
class SlackInteractionsController < ApplicationController
  skip_forgery_protection

  before_action :verify_slack_signature

  def create
    payload = JSON.parse(params[:payload])
    action = payload.dig("actions", 0)

    case action&.dig("action_id")
    when /^resolve_error_(\d+)$/
      resolve_error($1.to_i, payload)
    else
      head :ok
    end
  end

  private

  def resolve_error(error_id, payload)
    error = RailsErrorDashboard::ErrorLog.find_by(id: error_id)

    unless error
      respond_to_slack(payload, "Error ##{error_id} not found.")
      return
    end

    if error.resolved?
      respond_to_slack(payload, "Already resolved.")
      return
    end

    error.update!(resolved: true, resolved_at: Time.current)

    # Update the original Slack message to show it's resolved
    user_name = payload.dig("user", "name") || "Someone"
    respond_to_slack(payload, "Resolved by #{user_name}.")
  end

  # Respond by updating the original Slack message
  def respond_to_slack(payload, text)
    response_url = payload["response_url"]
    return head :ok unless response_url

    uri = URI(response_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request.body = {
      replace_original: false,
      text: text
    }.to_json

    http.request(request)
    head :ok
  end

  # Verify the request came from Slack using signing secret.
  # Slack sends interactions as form-encoded (payload=...), so we must
  # read the raw body before Rails parses it.
  def verify_slack_signature
    signing_secret = ENV["SLACK_SIGNING_SECRET"]
    return head :unauthorized unless signing_secret

    timestamp = request.headers["X-Slack-Request-Timestamp"]
    slack_signature = request.headers["X-Slack-Signature"]
    return head :unauthorized if timestamp.blank? || slack_signature.blank?

    # Reject requests older than 5 minutes (replay protection)
    return head :unauthorized if (Time.now.to_i - timestamp.to_i).abs > 300

    # Use request.raw_post which works even after Rails has parsed params
    raw_body = request.raw_post

    sig_basestring = "v0:#{timestamp}:#{raw_body}"
    my_signature = "v0=#{OpenSSL::HMAC.hexdigest("SHA256", signing_secret, sig_basestring)}"

    unless ActiveSupport::SecurityUtils.secure_compare(my_signature, slack_signature)
      Rails.logger.warn("[SlackInteractions] Signature mismatch")
      head :unauthorized
    end
  end
end
