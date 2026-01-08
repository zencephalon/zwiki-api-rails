require 'rails_helper'

RSpec.describe "Users", type: :request do
  describe "POST /users" do
    it "creates a new user" do
      post "/users", params: { user: { name: "Test", email: "test@example.com", password: "password123", password_confirmation: "password123" } }
      expect(response).to have_http_status(:created)
    end
  end

  describe "GET /users" do
    it "is not routable (security: no user enumeration)" do
      expect { get "/users" }.to raise_error(ActionController::RoutingError)
    end
  end
end
