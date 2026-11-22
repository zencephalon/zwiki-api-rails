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

  it "posts the task as JSON with the bearer token and explicit timeouts" do
    http = instance_double(Net::HTTP)
    sent_request = nil
    allow(Net::HTTP).to receive(:start).with(
      TreedoInbox::URL.host,
      TreedoInbox::URL.port,
      use_ssl: TreedoInbox::URL.scheme == 'https',
      open_timeout: 5,
      read_timeout: 15
    ).and_yield(http)
    allow(http).to receive(:request) do |req|
      sent_request = req
      response(Net::HTTPCreated, '201', '{"id":"abc"}')
    end

    expect(described_class.new.add("Call mom", "Sunday", today: true)).to eq('id' => 'abc')
    expect(sent_request['Authorization']).to eq('Bearer treedo_test')
    expect(sent_request['Content-Type']).to eq('application/json')
    expect(JSON.parse(sent_request.body)).to eq('title' => 'Call mom', 'notes' => 'Sunday', 'today' => true)
  end

  it "raises when treedo rejects the request, so the capture gets retried" do
    http = instance_double(Net::HTTP, request: response(Net::HTTPUnauthorized, '401', '{"error":"Unauthorized"}'))
    allow(Net::HTTP).to receive(:start).and_yield(http)

    expect { described_class.new.add("Call mom") }.to raise_error(TreedoInbox::Error, /401/)
  end
end
