require 'rails_helper'

RSpec.describe "Nodes", type: :request do
  let(:user) { User.create!(name: 'Nodes', email: 'nodes@example.com', password: 'password') }
  let(:auth) { { 'Authorization' => user.create_full_access_token.token } }

  it "returns 404 for an unknown short_id" do
    [[:get, "/nodes/nope"], [:patch, "/nodes/nope"], [:delete, "/nodes/nope"], [:post, "/nodes/nope/append"]].each do |verb, path|
      send(verb, path, params: { text: "x", version: 2 }, headers: auth)

      expect(response).to have_http_status(:not_found), "#{verb} #{path} returned #{response.status}"
      expect(JSON.parse(response.body)).to eq('error' => 'Node not found')
    end
  end

  describe "POST /nodes/:id/append" do
    let(:node) { user.nodes.create!(content: "# Note\n\nHello") }

    it "reports whether the text landed" do
      post "/nodes/#{CGI.escape(node.short_id)}/append", params: { text: " world" }, headers: auth
      expect(JSON.parse(response.body)).to include('appended' => true, 'content' => "# Note\n\nHello world")

      post "/nodes/#{CGI.escape(node.short_id)}/append", params: { text: " world" }, headers: auth
      expect(JSON.parse(response.body)).to include('appended' => false, 'content' => "# Note\n\nHello world")
    end
  end
end
