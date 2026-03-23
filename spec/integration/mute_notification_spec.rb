# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Muted error notification suppression", type: :request do
  let(:token) { "test-token" }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }
  let(:application) { RailsErrorDashboard::Application.find_or_create_by!(name: "getonbrd") }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("API_BEARER_TOKEN").and_return(token)

    RailsErrorDashboard.configure do |config|
      config.enable_slack_notifications = true
      config.slack_webhook_url = "https://hooks.slack.com/test"
      config.notification_cooldown_minutes = 0
      config.async_logging = false
    end
  end

  let(:error_payload) do
    {
      error: {
        error_type: "TestMuteError",
        message: "This error should be muted",
        severity: "error",
        platform: "ruby",
        backtrace: ["app/test.rb:1:in `test`"],
        occurred_at: Time.current.iso8601
      }
    }
  end

  it "sends Slack notification for unmuted errors" do
    expect(RailsErrorDashboard::SlackErrorNotificationJob).to receive(:perform_later).at_least(:once)

    post "/api/v1/errors", params: error_payload.to_json, headers: headers
    expect(response).to have_http_status(:created)
  end

  it "does NOT send Slack notification for muted errors" do
    # Create the error first
    post "/api/v1/errors", params: error_payload.to_json, headers: headers
    error_log = RailsErrorDashboard::ErrorLog.last

    # Mute it
    error_log.update!(muted: true, muted_at: Time.current)

    # Send the same error again — deduplication increments occurrence_count on the muted record
    expect(RailsErrorDashboard::SlackErrorNotificationJob).not_to receive(:perform_later)

    post "/api/v1/errors", params: error_payload.to_json, headers: headers
    expect(response).to have_http_status(:created)

    # Verify it was deduplicated (same record, higher count)
    expect(error_log.reload.occurrence_count).to be >= 2
    expect(error_log.muted).to be true
  end

  it "resumes Slack notifications after unmuting" do
    # Create and mute the error
    post "/api/v1/errors", params: error_payload.to_json, headers: headers
    error_log = RailsErrorDashboard::ErrorLog.last
    error_log.update!(muted: true, muted_at: Time.current)

    # Unmute it
    error_log.update!(muted: false, muted_at: nil)

    # Resolve it so the next occurrence triggers a "reopened" notification
    error_log.update!(resolved: true, resolved_at: Time.current)

    expect(RailsErrorDashboard::SlackErrorNotificationJob).to receive(:perform_later).at_least(:once)

    post "/api/v1/errors", params: error_payload.to_json, headers: headers
    expect(response).to have_http_status(:created)
  end
end
