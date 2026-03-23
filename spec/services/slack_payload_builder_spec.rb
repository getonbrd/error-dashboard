require "rails_helper"

RSpec.describe RailsErrorDashboard::Services::SlackPayloadBuilder do
  let(:application) { RailsErrorDashboard::Application.find_or_create_by!(name: "getonbrd") }

  let(:error_log) do
    RailsErrorDashboard::ErrorLog.create!(
      application: application,
      error_type: "NoMethodError",
      message: "undefined method `name' for nil:NilClass",
      backtrace: backtrace,
      platform: "ruby",
      occurred_at: Time.current,
      occurrence_count: 1,
      priority_level: 0,
      request_url: "https://app.getonbrd.com/dashboard",
      user_id: 42
    )
  end

  subject(:payload) { described_class.call(error_log) }

  context "with backtrace as newline-separated string" do
    let(:backtrace) do
      "/vendor/bundle/ruby/3.4.0/gems/actionpack-8.1.2/lib/action_controller.rb:321\n" \
      "app/controllers/dashboard_controller.rb:15:in `show'\n" \
      "app/middleware/auth.rb:8:in `call'"
    end

    it "builds a valid payload" do
      expect(payload[:text]).to include("NoMethodError")
      expect(payload[:blocks]).to be_an(Array)
    end

    it "includes header with severity emoji" do
      header = payload[:blocks].find { |b| b[:type] == "header" }
      expect(header[:text][:text]).to include("NoMethodError")
      expect(header[:text][:text]).to include(":white_circle:")
    end

    it "extracts first app/ line for stacktrace" do
      stacktrace = payload[:blocks].find { |b| b.dig(:text, :text)&.include?("Stacktrace") }
      expect(stacktrace[:text][:text]).to include("dashboard_controller.rb:15")
    end

    it "shows user info in info block" do
      info = payload[:blocks].find { |b| b[:type] == "context" && b[:elements]&.first&.dig(:text)&.include?("User") }
      expect(info[:elements].first[:text]).to include("User #42")
    end

    it "includes request URL" do
      request = payload[:blocks].find { |b| b.dig(:text, :text)&.include?("Request") }
      expect(request[:text][:text]).to include("app.getonbrd.com/dashboard")
    end

    it "includes resolve button" do
      actions = payload[:blocks].find { |b| b[:type] == "actions" }
      resolve_btn = actions[:elements].find { |e| e[:action_id]&.start_with?("resolve_error_") }
      expect(resolve_btn).to be_present
      expect(resolve_btn[:style]).to eq("danger")
    end
  end

  context "with backtrace as JSON array string" do
    let(:backtrace) do
      '["app/controllers/dashboard_controller.rb:15:in `show`","app/middleware/auth.rb:8:in `call`"]'
    end

    it "parses JSON and extracts stacktrace" do
      stacktrace = payload[:blocks].find { |b| b.dig(:text, :text)&.include?("Stacktrace") }
      expect(stacktrace[:text][:text]).to include("dashboard_controller.rb:15")
    end
  end

  context "with nil backtrace" do
    let(:backtrace) { nil }

    it "returns nil for stacktrace block" do
      stacktrace = payload[:blocks].find { |b| b.dig(:text, :text)&.include?("Stacktrace") }
      expect(stacktrace).to be_nil
    end
  end

  context "with empty backtrace" do
    let(:backtrace) { "" }

    it "returns nil for stacktrace block" do
      stacktrace = payload[:blocks].find { |b| b.dig(:text, :text)&.include?("Stacktrace") }
      expect(stacktrace).to be_nil
    end
  end

  context "with no app/ frames in backtrace" do
    let(:backtrace) { "/usr/local/bundle/gems/rack-3.0.0/lib/rack/handler.rb:10:in `call'" }

    it "falls back to first frame" do
      stacktrace = payload[:blocks].find { |b| b.dig(:text, :text)&.include?("Stacktrace") }
      expect(stacktrace[:text][:text]).to include("rack/handler.rb")
    end
  end

  context "with anonymous user" do
    let(:backtrace) { "app/controllers/test.rb:1" }

    let(:error_log) do
      RailsErrorDashboard::ErrorLog.create!(
        application: application,
        error_type: "RuntimeError",
        message: "test",
        backtrace: backtrace,
        platform: "ruby",
        occurred_at: Time.current,
        occurrence_count: 1,
        priority_level: 0,
        user_id: nil
      )
    end

    it "shows ghost emoji for anonymous" do
      info = payload[:blocks].find { |b| b[:type] == "context" && b[:elements]&.first&.dig(:text)&.include?("ghost") }
      expect(info).to be_present
    end
  end

  context "with recurring error" do
    let(:backtrace) { "app/controllers/test.rb:1" }

    let(:error_log) do
      RailsErrorDashboard::ErrorLog.create!(
        application: application,
        error_type: "RuntimeError",
        message: "test",
        backtrace: backtrace,
        platform: "ruby",
        occurred_at: Time.current,
        occurrence_count: 5,
        priority_level: 0
      )
    end

    it "shows occurrence count" do
      info = payload[:blocks].find { |b| b[:type] == "context" && b[:elements]&.first&.dig(:text)&.include?("5x") }
      expect(info).to be_present
    end
  end

  context "severity indicators" do
    let(:backtrace) { "app/test.rb:1" }

    {
      0 => ":white_circle:",
      1 => ":yellow_circle:",
      2 => ":large_orange_circle:",
      3 => ":red_circle:"
    }.each do |level, emoji|
      it "shows #{emoji} for priority_level #{level}" do
        error_log.update!(priority_level: level)
        header = payload[:blocks].find { |b| b[:type] == "header" }
        expect(header[:text][:text]).to include(emoji)
      end
    end
  end

  context "request block filtering" do
    let(:backtrace) { "app/test.rb:1" }

    it "hides non-URL request sources" do
      error_log.update!(request_url: "manual")
      request = payload[:blocks].find { |b| b.dig(:text, :text)&.include?("Request") }
      expect(request).to be_nil
    end

    it "shows http URLs" do
      error_log.update!(request_url: "https://app.getonbrd.com/test")
      request = payload[:blocks].find { |b| b.dig(:text, :text)&.include?("Request") }
      expect(request).to be_present
    end

    it "shows relative URLs" do
      error_log.update!(request_url: "/jobs/123")
      request = payload[:blocks].find { |b| b.dig(:text, :text)&.include?("Request") }
      expect(request).to be_present
    end
  end

  context "dashboard link" do
    let(:backtrace) { "app/test.rb:1" }

    it "includes dashboard link in context" do
      context_block = payload[:blocks].find { |b| b[:type] == "context" && b[:elements]&.first&.dig(:text)&.include?("error-dashboard") }
      expect(context_block).to be_present
    end
  end
end
