require 'rails_helper'

RSpec.describe "Captures", type: :request do
  describe "POST /capture" do
    it "accepts an unauthenticated request and logs headers and body" do
      allow(Rails.logger).to receive(:info).and_call_original

      post "/capture", params: { transcription: "buy batteries" }.to_json,
                       headers: { 'Content-Type' => 'application/json', 'X-Signature' => 'abc123' }

      expect(response).to have_http_status(:ok)
      expect(Rails.logger).to have_received(:info).with(a_string_including('X_SIGNATURE', 'abc123'))
      expect(Rails.logger).to have_received(:info).with(a_string_including('[capture] body', 'buy batteries'))
    end
  end
end
