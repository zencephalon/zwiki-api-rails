require 'net/http'
require 'json'

# Files a task in treedo's inbox (https://do.zencephalon.com). Raises on any
# failure so the capture request errors and the phone app retries delivery.
class TreedoInbox
  URL = URI(ENV.fetch('TREEDO_INBOX_URL', 'https://do.zencephalon.com/api/inbox'))

  class Error < StandardError; end

  # `today` also sets the task's *when* to today, so it shows on Today and comes up as a card.
  def add(title, notes = nil, today: false)
    response = Net::HTTP.post(
      URL,
      { title: title, notes: notes, today: today }.to_json,
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{ENV.fetch('TREEDO_TOKEN')}"
    )
    raise Error, "treedo inbox #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end
end
