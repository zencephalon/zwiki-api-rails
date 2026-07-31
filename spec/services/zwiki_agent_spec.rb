require 'rails_helper'

module AgentDoubles
  # Minimal stand-ins for the SDK's response objects. The agent only reads
  # #type/#text/#id/#name/#input off content blocks, plus #stop_reason and #usage.
  Text = Struct.new(:text) do
    def type = :text
  end

  ToolUse = Struct.new(:id, :name, :input) do
    def type = :tool_use
  end

  Usage = Struct.new(:input_tokens, :output_tokens)

  Message = Struct.new(:content, :stop_reason, :usage)

  # Replays a scripted list of messages, recording the request params it was given.
  class Client
    attr_reader :requests

    def initialize(script)
      @script = script.dup
      @requests = []
    end

    def messages = self

    def create(**params)
      # The agent keeps appending to the messages array it passed in, so snapshot
      # it here to capture what this particular request actually sent.
      @requests << params.merge(messages: params[:messages].dup)
      raise "AgentDoubles::Client ran out of scripted responses" if @script.empty?

      @script.shift
    end
  end
end

RSpec.describe ZwikiAgent do
  FakeClient = AgentDoubles::Client

  def text_message(text, stop_reason: :end_turn)
    AgentDoubles::Message.new([AgentDoubles::Text.new(text)], stop_reason, AgentDoubles::Usage.new(10, 20))
  end

  def tool_message(name, input, id: "toolu_1")
    AgentDoubles::Message.new([AgentDoubles::ToolUse.new(id, name, input)], :tool_use, AgentDoubles::Usage.new(10, 20))
  end

  let(:user) { User.create!(name: 'Test', email: 'agent@example.com', password: 'password') }

  def agent(script, allow_writes: false)
    described_class.new(user: user, allow_writes: allow_writes, client: FakeClient.new(script))
  end

  describe 'tool exposure' do
    it 'exposes only read tools to a read-only token' do
      names = agent([]).tools.map { |tool| tool[:name] }

      expect(names).to include('search_nodes', 'read_node', 'list_backlinks', 'list_recent_nodes')
      expect(names).not_to include('create_node', 'append_to_node', 'update_node')
    end

    it 'exposes write tools when writes are allowed' do
      names = agent([], allow_writes: true).tools.map { |tool| tool[:name] }

      expect(names).to include('create_node', 'append_to_node', 'update_node')
    end
  end

  describe '#run' do
    it 'returns the answer text when the model uses no tools' do
      result = agent([text_message("Nothing to look up.")]).run("hi")

      expect(result[:answer]).to eq("Nothing to look up.")
      expect(result[:tool_calls]).to be_empty
      expect(result[:nodes_touched]).to be_empty
      expect(result[:usage]).to eq(input_tokens: 10, output_tokens: 20)
    end

    it 'sends the query, tools, and system prompt on the first request' do
      client = FakeClient.new([text_message("done")])
      described_class.new(user: user, client: client).run("what did I write about ducks?")

      params = client.requests.first
      expect(params[:messages]).to eq([{ role: "user", content: "what did I write about ducks?" }])
      expect(params[:model]).to eq("claude-opus-5")
      expect(params[:thinking]).to eq(type: "adaptive")
      expect(params[:system_]).to include("Zwiki")
      expect(params[:tools].map { |tool| tool[:name] }).to include('search_nodes')
    end

    it 'raises when the model refuses' do
      expect { agent([text_message("", stop_reason: :refusal)]).run("q") }
        .to raise_error(described_class::Error, /declined/)
    end

    it 'gives up after the iteration cap' do
      script = Array.new(described_class::MAX_ITERATIONS) { tool_message("list_recent_nodes", {}) }

      expect { agent(script).run("q") }.to raise_error(described_class::Error, /Gave up/)
    end
  end

  describe 'read tools' do
    it 'searches nodes and feeds results back to the model' do
      user.nodes.create!(content: "# Duck Facts\n\nDucks have waterproof feathers.")
      client = FakeClient.new([
        tool_message("search_nodes", { "query" => "ducks" }),
        text_message("Ducks have waterproof feathers.")
      ])

      result = described_class.new(user: user, client: client).run("tell me about ducks")

      tool_result = client.requests.last[:messages].last[:content].first
      expect(tool_result[:content]).to include("Duck Facts", "waterproof")
      expect(tool_result[:is_error]).to be_nil
      expect(result[:tool_calls]).to eq([{ name: "search_nodes", input: { "query" => "ducks" } }])
    end

    it 'reports no matches without erroring' do
      client = FakeClient.new([
        tool_message("search_nodes", { "query" => "nonexistent" }),
        text_message("Nothing found.")
      ])
      described_class.new(user: user, client: client).run("q")

      tool_result = client.requests.last[:messages].last[:content].first
      expect(tool_result[:content]).to include("No nodes matched")
      expect(tool_result[:is_error]).to be_nil
    end

    it 'reads a node by short_id' do
      node = user.nodes.create!(content: "# Target\n\nBody text.")
      client = FakeClient.new([
        tool_message("read_node", { "short_id" => node.short_id }),
        text_message("Read it.")
      ])
      described_class.new(user: user, client: client).run("q")

      expect(client.requests.last[:messages].last[:content].first[:content]).to include("Body text.")
    end

    it 'lists backlinks' do
      target = user.nodes.create!(content: "# Target\n\nBody.")
      user.nodes.create!(content: "# Linker\n\nSee [Target](#{target.short_id}).")
      client = FakeClient.new([
        tool_message("list_backlinks", { "short_id" => target.short_id }),
        text_message("One backlink.")
      ])
      described_class.new(user: user, client: client).run("q")

      expect(client.requests.last[:messages].last[:content].first[:content]).to include("Linker")
    end

    it 'returns a tool error for an unknown short_id instead of raising' do
      client = FakeClient.new([
        tool_message("read_node", { "short_id" => "NOPE" }),
        text_message("Could not find it.")
      ])
      result = described_class.new(user: user, client: client).run("q")

      tool_result = client.requests.last[:messages].last[:content].first
      expect(tool_result[:is_error]).to be true
      expect(tool_result[:content]).to include("No node with short_id or name")
      expect(result[:answer]).to eq("Could not find it.")
    end

    it 'does not reach another user\'s nodes' do
      other = User.create!(name: 'Other', email: 'other@example.com', password: 'password')
      hidden = other.nodes.create!(content: "# Secret\n\nNot yours.")
      client = FakeClient.new([
        tool_message("read_node", { "short_id" => hidden.short_id }),
        text_message("No access.")
      ])
      described_class.new(user: user, client: client).run("q")

      tool_result = client.requests.last[:messages].last[:content].first
      expect(tool_result[:is_error]).to be true
      expect(tool_result[:content]).not_to include("Not yours")
    end
  end

  describe 'write tools' do
    it 'creates a node' do
      client = FakeClient.new([
        tool_message("create_node", { "content" => "# Fresh Node\n\nNew body." }),
        text_message("Created.")
      ])
      result = described_class.new(user: user, allow_writes: true, client: client).run("q")

      node = user.nodes.find_by(name: "Fresh Node")
      expect(node.content).to include("New body.")
      expect(result[:nodes_touched]).to eq([{ short_id: node.short_id, name: "Fresh Node", action: "created" }])
    end

    it 'appends to a node and bumps the version' do
      node = user.nodes.create!(content: "# Journal\n\nMorning.")
      client = FakeClient.new([
        tool_message("append_to_node", { "short_id" => node.short_id, "text" => "\n\nEvening." }),
        text_message("Appended.")
      ])
      result = described_class.new(user: user, allow_writes: true, client: client).run("q")

      expect(node.reload.content).to include("Morning.", "Evening.")
      expect(result[:nodes_touched].first[:action]).to eq("appended")
    end

    it 'replaces content on update and bumps the version' do
      node = user.nodes.create!(content: "# Old\n\nOld body.")
      before_version = node.version
      client = FakeClient.new([
        tool_message("update_node", { "short_id" => node.short_id, "content" => "# Old\n\nNew body." }),
        text_message("Updated.")
      ])
      described_class.new(user: user, allow_writes: true, client: client).run("q")

      expect(node.reload.content).to eq("# Old\n\nNew body.")
      expect(node.version).to be > before_version
    end

    it 'refuses writes for a read-only agent even if the model asks' do
      node = user.nodes.create!(content: "# Journal\n\nMorning.")
      client = FakeClient.new([
        tool_message("append_to_node", { "short_id" => node.short_id, "text" => "hacked" }),
        text_message("Could not write.")
      ])
      result = described_class.new(user: user, allow_writes: false, client: client).run("q")

      tool_result = client.requests.last[:messages].last[:content].first
      expect(tool_result[:is_error]).to be true
      expect(tool_result[:content]).to include("read-only")
      expect(node.reload.content).not_to include("hacked")
      expect(result[:nodes_touched]).to be_empty
    end
  end
end
