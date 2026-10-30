require 'rails_helper'

RSpec.describe "Public nodes", type: :request do
  let(:user) { FactoryBot.create(:user, password: "password123", password_confirmation: "password123") }

  it "serves a node whose slug contains dots" do
    node = user.nodes.create!(content: "# W. S. Merwin\n\nPoet", is_private: false)
    expect(node.slug).to eq("w.-s.-merwin")

    get "/public/node/#{node.slug}", headers: { "Authorization" => user.api_key }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["slug"]).to eq("w.-s.-merwin")
  end
end
