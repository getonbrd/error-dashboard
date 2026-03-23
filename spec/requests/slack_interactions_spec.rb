# frozen_string_literal: true

require "rails_helper"
require "net/http"

RSpec.describe "Slack Interactions", type: :request do
  let(:signing_secret) { "test-signing-secret" }
  let(:application) { RailsErrorDashboard::Application.find_or_create_by!(name: "getonbrd") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SLACK_SIGNING_SECRET").and_return(signing_secret)
    allow(RailsErrorDashboard::Commands::LogError).to receive(:call).and_return(nil)

    # Stub all outbound HTTP to Slack response_url
    allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
      instance_double(Net::HTTPSuccess, code: "200", body: "ok")
    )
  end

  def build_body(action_id:, error_id: 1, username: "testuser")
    payload = {
      actions: [{ action_id: action_id }],
      user: { username: username },
      response_url: "https://hooks.slack.com/actions/test/response",
      message: {
        ts: "1234567890.123456",
        blocks: [
          { type: "header", text: { type: "plain_text", text: "TestError" } },
          {
            type: "actions",
            elements: [
              { url: "https://github.com/test", type: "button", text: { type: "plain_text", text: "View Source" } },
              { action_id: "resolve_error_#{error_id}", type: "button", text: { type: "plain_text", text: "Resolve" } },
              { action_id: "mute_error_#{error_id}", type: "button", text: { type: "plain_text", text: "Mute" } }
            ]
          }
        ]
      }
    }
    "payload=#{CGI.escape(payload.to_json)}"
  end

  def signed_headers(body)
    timestamp = Time.now.to_i.to_s
    sig_basestring = "v0:#{timestamp}:#{body}"
    signature = "v0=#{OpenSSL::HMAC.hexdigest("SHA256", signing_secret, sig_basestring)}"

    {
      "Content-Type" => "application/x-www-form-urlencoded",
      "X-Slack-Request-Timestamp" => timestamp,
      "X-Slack-Signature" => signature
    }
  end

  describe "mute action" do
    let!(:error_log) do
      RailsErrorDashboard::ErrorLog.create!(
        application: application,
        error_type: "TestError",
        message: "test",
        platform: "ruby",
        occurred_at: Time.current,
        occurrence_count: 1,
        priority_level: 0
      )
    end

    it "mutes the error and records who muted it" do
      body = build_body(action_id: "mute_error_#{error_log.id}", error_id: error_log.id)

      post "/slack/interactions", params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:ok)
      expect(error_log.reload.muted).to be true
      expect(error_log.muted_by).to eq("testuser")
      expect(error_log.muted_reason).to eq("Muted from Slack")
    end

    it "responds with already muted when error is muted" do
      error_log.update!(muted: true, muted_at: Time.current)
      body = build_body(action_id: "mute_error_#{error_log.id}", error_id: error_log.id)

      post "/slack/interactions", params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:ok)
    end

    it "responds with not found for invalid error" do
      body = build_body(action_id: "mute_error_999999", error_id: 999999)

      post "/slack/interactions", params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:ok)
    end

    it "rejects requests without valid signature" do
      body = build_body(action_id: "mute_error_#{error_log.id}", error_id: error_log.id)

      post "/slack/interactions", params: body, headers: {
        "Content-Type" => "application/x-www-form-urlencoded",
        "X-Slack-Request-Timestamp" => Time.now.to_i.to_s,
        "X-Slack-Signature" => "v0=invalid"
      }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
