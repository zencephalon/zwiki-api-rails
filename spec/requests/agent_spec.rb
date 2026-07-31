require 'rails_helper'

RSpec.describe "Agent", type: :request do
  let(:user) { User.create!(name: 'Test', email: 'agent-request@example.com', password: 'password') }
  let(:full_access) { user.create_full_access_token.token }
  let(:read_only) { user.create_read_only_token.token }

  # Answers without touching the network.
  def stub_agent(answer: "stubbed answer")
    double = instance_double(ZwikiAgent, run: { answer: answer, tool_calls: [], nodes_touched: [] })
    allow(ZwikiAgent).to receive(:new).and_return(double)
    double
  end

  describe "POST /agent" do
    it "rejects an unauthenticated request" do
      post "/agent", params: { query: "hello" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "answers an authenticated query" do
      stub_agent(answer: "Ducks have waterproof feathers.")

      post "/agent", params: { query: "tell me about ducks" },
                     headers: { 'Authorization' => full_access }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['answer']).to eq("Ducks have waterproof feathers.")
    end

    it "requires a query" do
      post "/agent", params: { query: "  " }, headers: { 'Authorization' => full_access }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to match(/query is required/)
    end

    it "grants writes to a full access token" do
      stub_agent

      post "/agent", params: { query: "q" }, headers: { 'Authorization' => full_access }

      expect(ZwikiAgent).to have_received(:new).with(user: user, allow_writes: true)
    end

    it "withholds writes from a read-only token" do
      stub_agent

      post "/agent", params: { query: "q" }, headers: { 'Authorization' => read_only }

      expect(ZwikiAgent).to have_received(:new).with(user: user, allow_writes: false)
    end

    it "surfaces an agent error as 422" do
      allow(ZwikiAgent).to receive(:new).and_raise(ZwikiAgent::Error, "ANTHROPIC_API_KEY is not set")

      post "/agent", params: { query: "q" }, headers: { 'Authorization' => full_access }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to match(/ANTHROPIC_API_KEY/)
    end

    it "surfaces an upstream model error as 502" do
      error = Anthropic::Errors::APIStatusError.for(
        url: URI("https://api.anthropic.com"), status: 500,
        headers: nil, body: nil, request: nil, response: nil
      )
      allow(ZwikiAgent).to receive(:new).and_raise(error)

      post "/agent", params: { query: "q" }, headers: { 'Authorization' => full_access }

      expect(response).to have_http_status(:bad_gateway)
      expect(JSON.parse(response.body)['error']).to eq("Upstream model error")
    end
  end
end
