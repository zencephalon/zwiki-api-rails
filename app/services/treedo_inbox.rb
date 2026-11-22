require 'net/http'
require 'json'

# Files a task in treedo's inbox (https://do.zencephalon.com). Raises on any
# failure so the capture request errors and the phone app retries delivery.
class TreedoInbox
  URL = URI(ENV.fetch('TREEDO_INBOX_URL', 'https://do.zencephalon.com/api/inbox'))

  class Error < StandardError; end

  # `today` also sets the task's *when* to today, so it shows on Today and comes up as a card.
  def add(title, notes = nil, today: false)
    request = Net::HTTP::Post.new(URL)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{ENV.fetch('TREEDO_TOKEN')}"
    request.body = { title: title, notes: notes, today: today }.to_json

    response = Net::HTTP.start(
      URL.host,
      URL.port,
      use_ssl: URL.scheme == 'https',
      open_timeout: 5,
      read_timeout: 15
    ) { |http| http.request(request) }
    raise Error, "treedo inbox #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    return {} if response.body.to_s.strip.empty?

    JSON.parse(response.body)
  rescue JSON::ParserError
    {}
  end
end
