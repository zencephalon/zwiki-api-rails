class DailyJournal
  TIME_ZONE = ENV.fetch('CAPTURE_TIME_ZONE', 'America/New_York')

  def initialize(user)
    @user = user
  end

  def append(text, marker:, at: Time.current)
    now = at.in_time_zone(TIME_ZONE)
    # Matches zwiki's getDateStamp(): "Fri Oct 16 2026".
    name = now.strftime('%a %b %d %Y')
    node = @user.nodes.find_by(name: name) || @user.nodes.new(name: name).tap(&:fill_default_content).tap(&:save!)

    node.with_lock do
      node.content = "#{node.content.rstrip}\n\n#{now.strftime('%-I:%M:%S %p')} #{marker}: #{text}\n"
      node.version += 1
      node.save!
    end
    node
  end
end
