require 'rails_helper'

RSpec.describe CaptureRouter do
  def client_returning(json, stop_reason: :end_turn)
    block = double(type: :text, text: json)
    message = double(content: [block], stop_reason: stop_reason)
    client = double
    allow(client).to receive_message_chain(:messages, :create).and_return(message)
    client
  end

  it "routes a spoken task prefix straight to the inbox without calling Claude" do
    client = double
    result = described_class.new(client: client).route("Task: buy AA batteries")

    expect(result.tasks).to eq([{ title: "buy AA batteries", notes: nil, today: false }])
    expect(result.journal).to be_nil
  end

  ["Task today, buy milk", "Task for today: buy milk", "todo today buy milk"].each do |memo|
    it "puts #{memo.inspect} on today" do
      expect(described_class.new(client: double).route(memo).tasks).to eq([{ title: "buy milk", notes: nil, today: true }])
    end
  end

  ["Todo: buy AA batteries", "To do, buy AA batteries", "To-do. buy AA batteries"].each do |memo|
    it "treats #{memo.inspect} as a task" do
      expect(described_class.new(client: double).route(memo).tasks).to eq([{ title: "buy AA batteries", notes: nil, today: false }])
    end
  end

  it "routes a spoken journal prefix straight to the journal" do
    result = described_class.new(client: double).route("Journal, walked the dog at dusk.")

    expect(result.journal).to eq("walked the dog at dusk.")
    expect(result.tasks).to be_empty
  end

  it "splits an unprefixed memo using the classifier" do
    json = {
      journal: "Walked the dog, felt great.",
      tasks: [{ title: "Buy batteries", notes: "", today: false }, { title: "Call the bank", notes: "", today: true }]
    }.to_json
    result = described_class.new(client: client_returning(json)).route("walked the dog, felt great, oh and buy batteries")

    expect(result.journal).to eq("Walked the dog, felt great.")
    expect(result.tasks).to eq([
      { title: "Buy batteries", notes: nil, today: false },
      { title: "Call the bank", notes: nil, today: true }
    ])
  end

  it "falls back to an inbox task when the classifier refuses" do
    result = described_class.new(client: client_returning("", stop_reason: :refusal)).route("something odd")

    expect(result.tasks).to eq([{ title: "something odd", notes: nil, today: false }])
    expect(result.journal).to be_nil
  end

  it "falls back to an inbox task when the classifier returns bad JSON" do
    result = described_class.new(client: client_returning("not json")).route("something odd")

    expect(result.tasks).to eq([{ title: "something odd", notes: nil, today: false }])
  end
end
