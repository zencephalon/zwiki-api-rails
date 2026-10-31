require 'rails_helper'

RSpec.describe "Journal", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(name: 'Journal', email: 'journal@example.com', password: 'password') }
  let(:append_only) { user.create_append_only_token.token }
  let(:auth) { { 'Authorization' => append_only } }

  describe "POST /journal/today" do
    it "creates today's entry in the journal time zone from the template" do
      user.nodes.create!(content: "# __journal_template__\n\n## Gratitude")

      travel_to Time.zone.parse('2026-10-17 01:14 UTC') do
        post "/journal/today", params: { text: "Ran the numbers." }, headers: auth
      end

      expect(response).to have_http_status(:created)
      node = user.nodes.find_by!(name: 'Fri Oct 16 2026')
      expect(node.content).to eq("# Fri Oct 16 2026\n\n## Gratitude\n\n9:14:00 PM 🤖: Ran the numbers.\n")
      expect(JSON.parse(response.body)).to eq('id' => node.short_id, 'name' => node.name, 'version' => node.version)
    end

    it "appends to an existing entry even when the text repeats" do
      node = user.nodes.create!(content: "# Fri Oct 16 2026\n\nMorning.")
      version = node.reload.version

      travel_to Time.zone.parse('2026-10-16 09:05 -04:00') do
        2.times { post "/journal/today", params: { text: "Same." }, headers: auth }
      end

      node.reload
      expect(node.content.scan("9:05:00 AM 🤖: Same.").size).to eq(2)
      expect(node.version).to eq(version + 2)
    end

    it "rejects blank text" do
      post "/journal/today", params: { text: "  " }, headers: auth

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "accepts a full-access token" do
      post "/journal/today", params: { text: "Hi." }, headers: { 'Authorization' => user.create_full_access_token.token }

      expect(response).to have_http_status(:created)
    end

    it "rejects a read-only token and no token" do
      post "/journal/today", params: { text: "Hi." }, headers: { 'Authorization' => user.create_read_only_token.token }
      expect(response).to have_http_status(:forbidden)

      post "/journal/today", params: { text: "Hi." }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "an append-only token elsewhere" do
    let(:node) { user.nodes.create!(content: "# Secret\n\nKeep out.") }

    it "cannot read, search, ask the agent, or manage tokens" do
      requests = [
        [:get, "/nodes", {}],
        [:get, "/nodes/#{CGI.escape(node.short_id)}", {}],
        [:get, "/nodes/search", { q: "Secret" }],
        [:get, "/users/me", {}],
        [:get, "/tokens", {}],
        [:post, "/tokens/append_only", {}],
        [:post, "/agent", { query: "read my secrets" }],
        [:post, "/nodes", { content: "# New" }],
        [:post, "/nodes/#{CGI.escape(node.short_id)}/append", { text: "x" }],
        [:delete, "/nodes/#{CGI.escape(node.short_id)}", {}]
      ]

      requests.each do |verb, path, params|
        send(verb, path, params: params, headers: auth)
        expect(response).to have_http_status(:forbidden), "#{verb} #{path} returned #{response.status}"
      end
      expect(user.nodes.exists?(node.id)).to be(true)
    end
  end

  describe "POST /tokens/append_only" do
    it "lets a full-access token mint one that never expires" do
      post "/tokens/append_only", headers: { 'Authorization' => user.create_full_access_token.token }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['token_type']).to eq('append_only')
      expect(body['expires_at']).to be_nil
    end

    it "refuses a read-only token" do
      post "/tokens/append_only", headers: { 'Authorization' => user.create_read_only_token.token }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
