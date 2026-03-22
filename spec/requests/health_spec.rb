require "rails_helper"

RSpec.describe "Health", type: :request do
  describe "GET /health" do
    it "returns 200 when database is connected" do
      get "/health"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("ok")
    end

    it "returns 503 when database is down" do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(PG::ConnectionBad, "connection refused")

      get "/health"

      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body)["status"]).to eq("error")
    end
  end
end
