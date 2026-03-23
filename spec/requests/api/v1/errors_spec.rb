require "rails_helper"

RSpec.describe "Api::V1::Errors", type: :request do
  let(:token) { "test-bearer-token" }
  let(:headers) do
    {
      "Authorization" => "Bearer #{token}",
      "Content-Type" => "application/json"
    }
  end
  let(:valid_error) do
    {
      error: {
        error_type: "NoMethodError",
        message: "undefined method 'foo' for nil",
        backtrace: ["app/models/user.rb:42:in 'process'"],
        severity: "error",
        platform: "ruby",
        source: "getonbrd",
        app_version: "sha-abc1234",
        user_id: "42",
        request_url: "/jobs/123",
        ip_address: "1.2.3.4",
        user_agent: "Mozilla/5.0",
        metadata: { controller: "jobs", action: "show" }
      }
    }
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("API_BEARER_TOKEN").and_return(token)
  end

  describe "GET /api/v1/errors" do
    before do
      allow(RailsErrorDashboard::ManualErrorReporter).to receive(:report).and_return(nil)
    end

    let!(:application) { RailsErrorDashboard::Application.find_or_create_by!(name: "getonbrd") }
    let!(:error_log) do
      RailsErrorDashboard::ErrorLog.create!(
        error_type: "TestError",
        message: "test message",
        backtrace: ["app/test.rb:1"],
        platform: "ruby",
        app_version: "sha-abc1234",
        application: application,
        occurred_at: Time.current,
        first_seen_at: Time.current,
        last_seen_at: Time.current,
        occurrence_count: 1,
        error_hash: SecureRandom.hex(16)
      )
    end

    it "returns paginated errors" do
      get "/api/v1/errors", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["errors"].length).to be >= 1
      expect(body["meta"]["page"]).to eq(1)
      expect(body["meta"]["total"]).to be >= 1
    end

    it "filters by error_type" do
      get "/api/v1/errors", params: { error_type: "TestError" }, headers: headers

      body = JSON.parse(response.body)
      expect(body["errors"].all? { |e| e["error_type"] == "TestError" }).to be true
    end

    it "requires authentication" do
      get "/api/v1/errors", headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/errors/:id" do
    let!(:application) { RailsErrorDashboard::Application.find_or_create_by!(name: "getonbrd") }
    let!(:error_log) do
      RailsErrorDashboard::ErrorLog.create!(
        error_type: "DetailError",
        message: "detailed test",
        backtrace: ["app/test.rb:1"],
        platform: "ruby",
        application: application,
        occurred_at: Time.current,
        first_seen_at: Time.current,
        last_seen_at: Time.current,
        occurrence_count: 1,
        error_hash: SecureRandom.hex(16)
      )
    end

    it "returns error details with backtrace" do
      get "/api/v1/errors/#{error_log.id}", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["error"]
      expect(body["error_type"]).to eq("DetailError")
      expect(body["backtrace"]).to be_present
    end

    it "returns 404 for missing error" do
      get "/api/v1/errors/99999", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/errors/#{error_log.id}", headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/errors" do
    context "with valid token" do
      it "returns 201 accepted" do
        allow(RailsErrorDashboard::ManualErrorReporter).to receive(:report)

        post "/api/v1/errors", params: valid_error.to_json, headers: headers

        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)["status"]).to eq("accepted")
      end

      it "calls ManualErrorReporter with correct params" do
        expect(RailsErrorDashboard::ManualErrorReporter).to receive(:report).with(
          error_type: "NoMethodError",
          message: "undefined method 'foo' for nil",
          backtrace: ["app/models/user.rb:42:in 'process'"],
          platform: "ruby",
          user_id: "42",
          request_url: "/jobs/123",
          user_agent: "Mozilla/5.0",
          ip_address: "1.2.3.4",
          app_version: "sha-abc1234",
          metadata: '{"controller":"jobs","action":"show"}',
          occurred_at: nil,
          severity: :error,
          source: "getonbrd"
        )

        post "/api/v1/errors", params: valid_error.to_json, headers: headers
      end

      it "accepts minimal params" do
        allow(RailsErrorDashboard::ManualErrorReporter).to receive(:report)

        post "/api/v1/errors",
          params: { error: { error_type: "TestError", message: "test" } }.to_json,
          headers: headers

        expect(response).to have_http_status(:created)
      end
    end

    context "with invalid token" do
      it "returns 401 unauthorized" do
        post "/api/v1/errors",
          params: valid_error.to_json,
          headers: headers.merge("Authorization" => "Bearer wrong-token")

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("Unauthorized")
      end
    end

    context "with missing token" do
      it "returns 401 unauthorized" do
        post "/api/v1/errors",
          params: valid_error.to_json,
          headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with missing error key" do
      it "returns 400 bad request" do
        post "/api/v1/errors",
          params: {}.to_json,
          headers: headers

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe "POST /api/v1/errors/batch" do
    context "with valid token" do
      it "returns 201 with count" do
        allow(RailsErrorDashboard::ManualErrorReporter).to receive(:report)

        post "/api/v1/errors/batch",
          params: {
            errors: [
              { error_type: "Error1", message: "first" },
              { error_type: "Error2", message: "second" }
            ]
          }.to_json,
          headers: headers

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["total"]).to eq(2)
      end

      it "calls ManualErrorReporter for each error" do
        expect(RailsErrorDashboard::ManualErrorReporter).to receive(:report).twice

        post "/api/v1/errors/batch",
          params: {
            errors: [
              { error_type: "Error1", message: "first" },
              { error_type: "Error2", message: "second" }
            ]
          }.to_json,
          headers: headers
      end
    end

    context "with invalid token" do
      it "returns 401 unauthorized" do
        post "/api/v1/errors/batch",
          params: { errors: [] }.to_json,
          headers: headers.merge("Authorization" => "Bearer wrong")

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
