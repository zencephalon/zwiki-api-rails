require 'rails_helper'

RSpec.describe "Captures", type: :request do
  let!(:user) { User.create!(name: 'Capture', email: 'capture-request@example.com', password: 'password') }
  let(:token) { 'capture-secret' }
  let(:processor) { instance_double(CaptureProcessor) }
  let(:result) { CaptureRouter::Result.new(journal: "Walked the dog.", tasks: [{ title: "Buy batteries", notes: nil }]) }

  around do |example|
    original = ENV.to_h.slice('CAPTURE_SECRET', 'CAPTURE_USER_ID')
    ENV['CAPTURE_SECRET'] = token
    ENV['CAPTURE_USER_ID'] = user.id.to_s
    example.run
  ensure
    %w[CAPTURE_SECRET CAPTURE_USER_ID].each { |k| original.key?(k) ? ENV[k] = original[k] : ENV.delete(k) }
  end

  before do
    allow(CaptureProcessor).to receive(:new).and_return(processor)
    allow(processor).to receive(:process).and_return(result)
  end

  def post_capture(params, headers = {})
    post "/capture", params: params, headers: { 'X-Capture-Token' => token }.merge(headers)
  end

  it "rejects a request without the capture token" do
    post "/capture", params: { transcription: "buy batteries" }

    expect(response).to have_http_status(:unauthorized)
    expect(processor).not_to have_received(:process)
  end

  it "rejects a request with the wrong capture token" do
    post_capture({ transcription: "buy batteries" }, 'X-Capture-Token' => 'nope')

    expect(response).to have_http_status(:unauthorized)
  end

  it "acknowledges test events without routing them" do
    post_capture(transcription: "Index webhook test event", test: "true", client: "ring")

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include('test' => true)
    expect(processor).not_to have_received(:process)
  end

  it "routes the transcription, timestamped by recordedAt" do
    post_capture(transcription: "walked the dog, buy batteries", recordedAt: "1792186850159", client: "ring")

    expect(response).to have_http_status(:ok)
    expect(processor).to have_received(:process).with("walked the dog, buy batteries", at: Time.zone.at(1792186850.159))
    expect(JSON.parse(response.body)).to include('journal' => "Walked the dog.", 'tasks' => ["Buy batteries"])
  end

  it "skips a redelivered event" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    headers = { 'X-Index-Delivery' => 'd9c8883d-105b-40b1-96d7-a0876255af9e' }

    2.times { post_capture({ transcription: "buy batteries" }, headers) }

    expect(processor).to have_received(:process).once
    expect(JSON.parse(response.body)).to include('duplicate' => true)
  end
end
