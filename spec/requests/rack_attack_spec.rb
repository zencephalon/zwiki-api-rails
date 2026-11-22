require 'rails_helper'

RSpec.describe "Rate limiting", type: :request do
  let(:user) { FactoryBot.create(:user, password: "password123", password_confirmation: "password123") }

  include ActiveSupport::Testing::TimeHelpers

  # Rack::Attack counts in fixed 5s buckets; a burst straddling two never trips.
  before do
    Rack::Attack.reset!
    freeze_time
  end

  after do
    Rack::Attack.reset!
    travel_back
  end

  def statuses(headers = {})
    25.times.map do
      get "/public/index", headers: headers
      response.status
    end
  end

  it "throttles requests without a token" do
    expect(statuses).to include(429)
  end

  it "throttles requests with an unknown token" do
    expect(statuses("Authorization" => "nope")).to include(429)
  end

  it "throttles requests with an expired token" do
    token = ApiToken.create!(user: user, token_type: "full_access", expires_at: 1.day.ago)
    expect(statuses("Authorization" => token.token)).to include(429)
  end

  it "never throttles an active api token" do
    token = ApiToken.create!(user: user, token_type: "read_only")
    expect(statuses("Authorization" => token.token)).to all(eq(200))
  end

  it "never throttles a legacy api key" do
    expect(statuses("Authorization" => user.api_key)).to all(eq(200))
  end

  it "throttles repeated login attempts" do
    codes = 12.times.map do
      post "/login", params: { name: "nobody", password: "wrong" }
      response.status
    end
    expect(codes).to include(429)
  end

  it "throttles AI endpoints even with an active api token" do
    token = ApiToken.create!(user: user, token_type: "full_access")
    codes = 22.times.map do
      post "/agent", params: { query: "  " }, headers: { "Authorization" => token.token }
      response.status
    end
    expect(codes).to include(429)
  end
end
