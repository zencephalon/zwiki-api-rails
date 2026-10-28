require 'rails_helper'

RSpec.describe TreedoInbox do
  around do |example|
    original = ENV['TREEDO_TOKEN']
    ENV['TREEDO_TOKEN'] = 'treedo_test'
    example.run
  ensure
    original ? ENV['TREEDO_TOKEN'] = original : ENV.delete('TREEDO_TOKEN')
  end

  def response(klass, code, body)
    klass.new('1.1', code, '').tap { |r| allow(r).to receive(:body).and_return(body) }
  end

  it "posts the task as JSON with the bearer token" do
    allow(Net::HTTP).to receive(:post).and_return(response(Net::HTTPCreated, '201', '{"id":"abc"}'))

    expect(described_class.new.add("Call mom", "Sunday", today: true)).to eq('id' => 'abc')
    expect(Net::HTTP).to have_received(:post).with(
      TreedoInbox::URL,
      { title: "Call mom", notes: "Sunday", today: true }.to_json,
      hash_including('Authorization' => 'Bearer treedo_test', 'Content-Type' => 'application/json')
    )
  end

  it "raises when treedo rejects the request, so the capture gets retried" do
    allow(Net::HTTP).to receive(:post).and_return(response(Net::HTTPUnauthorized, '401', '{"error":"Unauthorized"}'))

    expect { described_class.new.add("Call mom") }.to raise_error(TreedoInbox::Error, /401/)
  end
end
