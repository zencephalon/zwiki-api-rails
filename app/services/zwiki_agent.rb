class ZwikiAgent
  MODEL = "claude-opus-5"
  MAX_TOKENS = 16_000
  EFFORT = "medium"
  MAX_ITERATIONS = 12
  SEARCH_LIMIT = 25

  class Error < StandardError; end

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You answer questions about the user's personal knowledge base (Zwiki), a graph of
    markdown nodes. Each node has a short_id (e.g. "ABC123"), a name taken from its
    first `# Title` line, and markdown content. Nodes link to each other with
    `[Link Text](short_id)` and embed each other with `{Text}(short_id)`.

    Search is Postgres full-text over name and content. It matches on any word and on
    prefixes, so prefer several short queries with distinct keywords over one long
    query. When a search returns something promising, read the full node before
    answering from the snippet alone.

    Journal entries are named like "Fri Nov 25 2022". To find one, search for that
    exact name.

    A short_id may contain unusual Unicode characters. Copy it character-for-character
    from tool output — never retype, transliterate, or guess one. Where a tool takes a
    short_id U may pass a node's exact name instead, which is safer when the short_id
    looks ambiguous.

    Answer from what U actually read. Cite the nodes U used by short_id and name.
    If the knowledge base does not contain the answer, say so plainly rather than
    answering from general knowledge.

    Deliver what the user asked for, at the scope they intended. Make routine judgment
    calls yourself; check in only when different readings would lead to materially
    different work. Do not make edits the user did not ask for.

    Keep the final answer focused and brief. Lead with the answer, then supporting
    detail. Skip preamble.
  PROMPT

  READ_TOOLS = [
    {
      name: "search_nodes",
      description: "Full-text search the user's nodes by keyword. Returns short_id, name, " \
                   "and a content snippet for each match, best match first. Use several " \
                   "focused queries rather than one long one.",
      input_schema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Keywords to search for." },
          limit: { type: "integer", description: "Max results, 1-#{SEARCH_LIMIT}. Defaults to 10." }
        },
        required: ["query"]
      }
    },
    {
      name: "read_node",
      description: "Read a node's full markdown content by short_id.",
      input_schema: {
        type: "object",
        properties: { short_id: { type: "string" } },
        required: ["short_id"]
      }
    },
    {
      name: "list_backlinks",
      description: "List the nodes that link to a given node. Use this to explore how an " \
                   "idea connects to the rest of the knowledge base.",
      input_schema: {
        type: "object",
        properties: { short_id: { type: "string" } },
        required: ["short_id"]
      }
    },
    {
      name: "list_recent_nodes",
      description: "List the most recently updated nodes. Use for questions about what the " \
                   "user has been working on lately.",
      input_schema: {
        type: "object",
        properties: {
          limit: { type: "integer", description: "Max results, 1-#{SEARCH_LIMIT}. Defaults to 10." }
        },
        required: []
      }
    }
  ].freeze

  WRITE_TOOLS = [
    {
      name: "create_node",
      description: "Create a new node. The content must start with a `# Title` line; the " \
                   "node's name is taken from it. Returns the new node's short_id.",
      input_schema: {
        type: "object",
        properties: {
          content: { type: "string", description: "Full markdown content, starting with `# Title`." }
        },
        required: ["content"]
      }
    },
    {
      name: "append_to_node",
      description: "Append text to the end of an existing node. Non-destructive: prefer this " \
                   "over update_node when adding information.",
      input_schema: {
        type: "object",
        properties: {
          short_id: { type: "string" },
          text: { type: "string", description: "Markdown to append verbatim." }
        },
        required: %w[short_id text]
      }
    },
    {
      name: "update_node",
      description: "Replace a node's entire content. Destructive — read the node first and " \
                   "preserve everything that should survive the edit. Prefer append_to_node " \
                   "when U are only adding information.",
      input_schema: {
        type: "object",
        properties: {
          short_id: { type: "string" },
          content: { type: "string", description: "The node's complete new markdown content." }
        },
        required: %w[short_id content]
      }
    }
  ].freeze

  attr_reader :tool_calls, :nodes_touched

  def initialize(user:, allow_writes: false, client: nil)
    @user = user
    @allow_writes = allow_writes
    @client = client || self.class.build_client
    @tool_calls = []
    @nodes_touched = []
  end

  def self.build_client
    key = ENV["ANTHROPIC_API_KEY"]
    raise Error, "ANTHROPIC_API_KEY is not set" if key.blank?

    Anthropic::Client.new(api_key: key)
  end

  def tools
    @allow_writes ? READ_TOOLS + WRITE_TOOLS : READ_TOOLS
  end

  def run(query)
    messages = [{ role: "user", content: query }]

    MAX_ITERATIONS.times do
      message = @client.messages.create(
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system_: SYSTEM_PROMPT,
        thinking: { type: "adaptive" },
        output_config: { effort: EFFORT },
        tools: tools,
        messages: messages
      )

      raise Error, "The model declined this request." if message.stop_reason == :refusal

      messages << { role: "assistant", content: message.content }

      requests = message.content.select { |block| block.type == :tool_use }
      return answer_from(message) if requests.empty?

      messages << { role: "user", content: requests.map { |request| run_tool(request) } }
    end

    raise Error, "Gave up after #{MAX_ITERATIONS} steps without reaching an answer."
  end

  private

  def answer_from(message)
    text = message.content.select { |block| block.type == :text }.map(&:text).join("\n").strip

    {
      answer: text,
      tool_calls: @tool_calls,
      nodes_touched: @nodes_touched.uniq,
      usage: {
        input_tokens: message.usage.input_tokens,
        output_tokens: message.usage.output_tokens
      }
    }
  end

  def run_tool(request)
    input = request.input.is_a?(Hash) ? request.input.transform_keys(&:to_s) : {}
    result = dispatch(request.name, input)
    @tool_calls << { name: request.name, input: input }
    { type: "tool_result", tool_use_id: request.id, content: result }
  rescue StandardError => e
    Rails.logger.warn("ZwikiAgent tool #{request.name} failed: #{e.class}: #{e.message}")
    @tool_calls << { name: request.name, input: input, error: e.message }
    { type: "tool_result", tool_use_id: request.id, content: "Error: #{e.message}", is_error: true }
  end

  def dispatch(name, input)
    case name
    when "search_nodes"      then tool_search_nodes(input)
    when "read_node"         then tool_read_node(input)
    when "list_backlinks"    then tool_list_backlinks(input)
    when "list_recent_nodes" then tool_list_recent_nodes(input)
    when "create_node"       then tool_create_node(input)
    when "append_to_node"    then tool_append_to_node(input)
    when "update_node"       then tool_update_node(input)
    else raise Error, "Unknown tool #{name}"
    end
  end

  def tool_search_nodes(input)
    query = input["query"].to_s
    raise Error, "query is required" if query.strip.empty?

    nodes = @user.nodes.search_for(query).limit(clamp(input["limit"]))
    return "No nodes matched #{query.inspect}." if nodes.empty?

    nodes.map do |node|
      "#{node.short_id} — #{node.name}\n#{snippet(node.content)}"
    end.join("\n\n")
  end

  def tool_read_node(input)
    node = find_node(input["short_id"])
    "#{node.short_id} — #{node.name} (version #{node.version})\n\n#{node.content}"
  end

  def tool_list_backlinks(input)
    node = find_node(input["short_id"])
    backlinks = @user.nodes.tagged_with(node.short_id, on: :links)
    return "Nothing links to #{node.short_id}." if backlinks.empty?

    backlinks.map { |linker| "#{linker.short_id} — #{linker.name}" }.join("\n")
  end

  def tool_list_recent_nodes(input)
    nodes = @user.nodes.order(updated_at: :desc).limit(clamp(input["limit"]))
    return "This knowledge base has no nodes." if nodes.empty?

    nodes.map do |node|
      "#{node.short_id} — #{node.name} (updated #{node.updated_at.to_date.iso8601})"
    end.join("\n")
  end

  def tool_create_node(input)
    require_writes!
    content = input["content"].to_s
    raise Error, "content is required" if content.strip.empty?

    node = @user.nodes.create!(content: content)
    node.reload
    @nodes_touched << { short_id: node.short_id, name: node.name, action: "created" }
    "Created #{node.short_id} — #{node.name}"
  end

  def tool_append_to_node(input)
    require_writes!
    text = input["text"].to_s
    raise Error, "text is required" if text.empty?

    node = find_node(input["short_id"])
    before = node.content
    node.append(text)
    return "#{node.short_id} already contained that text; nothing appended." if node.content == before

    node.save!
    @nodes_touched << { short_id: node.short_id, name: node.name, action: "appended" }
    "Appended to #{node.short_id} — #{node.name} (now version #{node.version})"
  end

  def tool_update_node(input)
    require_writes!
    content = input["content"].to_s
    raise Error, "content is required" if content.strip.empty?

    node = find_node(input["short_id"])
    return "#{node.short_id} already had that exact content; nothing changed." if node.content == content

    node.content = content
    node.version += 1
    node.save!
    @nodes_touched << { short_id: node.short_id, name: node.name, action: "updated" }
    "Updated #{node.short_id} — #{node.name} (now version #{node.version})"
  end

  def require_writes!
    raise Error, "This token is read-only; it cannot modify nodes." unless @allow_writes
  end

  # Short_ids are drawn from a wide Unicode alphabet, which models reproduce
  # unreliably, so fall back to an exact name match before giving up.
  def find_node(identifier)
    key = identifier.to_s
    node = @user.nodes.find_by(short_id: key) || @user.nodes.find_by(name: key)
    raise Error, "No node with short_id or name #{key.inspect}" unless node

    node
  end

  def clamp(limit)
    value = limit.to_i
    return 10 if value <= 0

    [value, SEARCH_LIMIT].min
  end

  def snippet(content, length: 400)
    body = content.to_s.strip
    body.length > length ? "#{body[0, length]}…" : body
  end
end
