require 'rails_helper'

RSpec.describe "Users", type: :request do
  describe "open registration" do
    it "does not expose POST /users or POST /register" do
      expect { post "/users", params: { user: { name: "Test", email: "test@example.com", password: "password123", password_confirmation: "password123" } } }
        .to raise_error(ActionController::RoutingError)
      expect { post "/register", params: { name: "Test", email: "test@example.com", password: "password123", password_confirmation: "password123" } }
        .to raise_error(ActionController::RoutingError)
    end
  end

  describe "GET /users" do
    it "is not routable (security: no user enumeration)" do
      expect { get "/users" }.to raise_error(ActionController::RoutingError)
    end
  end

  describe "DELETE /users/me" do
    it "deletes the user along with owned nodes, questlogs, and quest" do
      user = User.create!(name: "DeleteMe", email: "delete@example.com", password: "password123")
      user.questlogs.create!(description: "did thing", private: true)
      Quest.create!(user: user, blob: { a: 1 })
      token = user.create_full_access_token.token

      delete "/users/me", headers: { "Authorization" => token }

      expect(response).to have_http_status(:no_content)
      expect(User.exists?(user.id)).to be(false)
    end
  end
end
