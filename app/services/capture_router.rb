require 'json'

# Splits a voice-memo transcript into a journal fragment and treedo inbox tasks.
# A spoken "task …" or "journal …" prefix decides outright; otherwise Claude
# classifies. Any classifier failure sends the raw text to the inbox, since a
# stray inbox item costs one swipe while a task buried in the journal gets lost.
class CaptureRouter
  MODEL = 'claude-opus-5-5'.freeze

  TASK_PREFIX = /\A\s*(?:task|to[- ]?do)\b[\s:,.\-]*/i
  JOURNAL_PREFIX = /\A\s*journal\b[\s:,.\-]*/i

  SYSTEM_PROMPT = <<~PROMPT.freeze
    U route voice memos the user dictated into a ring-mounted recorder. Split the
    transcript into two destinations:

    - journal: reflections, events, feelings, observations, ideas worth remembering.
      Keep the speaker's own words; fix only obvious transcription slips.
    - tasks: concrete actions the speaker intends to take later. Give each a short
      imperative title; put any useful context (who, where, when, why) in notes.

    One memo may feed both. Use an empty string for journal when nothing belongs
    there, and an empty list for tasks when nothing does. When a fragment could go
    either way, make it a task.
  PROMPT

  SCHEMA = {
    type: 'object',
    properties: {
      journal: { type: 'string' },
      tasks: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            title: { type: 'string' },
            notes: { type: 'string' }
          },
          required: %w[title notes],
          additionalProperties: false
        }
      }
    },
    required: %w[journal tasks],
    additionalProperties: false
  }.freeze

  Result = Struct.new(:journal, :tasks, keyword_init: true)

  def initialize(client: nil)
    @client = client
  end

  def route(text)
    text = text.to_s.strip
    return Result.new(journal: nil, tasks: []) if text.empty?

    if (match = text.match(TASK_PREFIX))
      Result.new(journal: nil, tasks: [{ title: match.post_match.strip, notes: nil }])
    elsif (match = text.match(JOURNAL_PREFIX))
      Result.new(journal: match.post_match.strip, tasks: [])
    else
      classify(text)
    end
  end

  private

  def classify(text)
    message = client.messages.create(
      model: MODEL,
      max_tokens: 4000,
      system_: SYSTEM_PROMPT,
      output_config: { effort: :low, format_: { type: :json_schema, schema: SCHEMA } },
      messages: [{ role: 'user', content: text }]
    )
    return fallback(text) unless message.stop_reason == :end_turn

    data = JSON.parse(message.content.select { |b| b.type == :text }.map(&:text).join)
    tasks = data['tasks'].map { |t| { title: t['title'], notes: t['notes'].presence } }
    Result.new(journal: data['journal'].presence, tasks: tasks)
  rescue Anthropic::Errors::Error, JSON::ParserError => e
    Rails.logger.warn("[capture] classifier failed, sending to the inbox: #{e.class}: #{e.message}")
    fallback(text)
  end

  def fallback(text)
    Result.new(journal: nil, tasks: [{ title: text, notes: nil }])
  end

  def client
    @client ||= ZwikiAgent.build_client
  end
end
