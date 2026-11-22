require 'zlib'

class DailyJournal
  TIME_ZONE = ENV.fetch('CAPTURE_TIME_ZONE', 'America/New_York')

  def initialize(user)
    @user = user
  end

  def append(text, marker:, at: Time.current)
    now = at.in_time_zone(TIME_ZONE)
    # Matches zwiki's getDateStamp(): "Fri Oct 16 2026".
    name = now.strftime('%a %b %d %Y')
    lock_key = Zlib.crc32(name) & 0x7fffffff

    @user.transaction do
      # Serialize find-or-create per (user, day) so concurrent captures never
      # create duplicate journal nodes.
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(?, ?)', @user.id, lock_key])
      )
      node = @user.nodes.find_by(name: name) || @user.nodes.new(name: name).tap(&:fill_default_content).tap(&:save!)
      node.lock!
      node.content = "#{node.content.rstrip}\n\n#{now.strftime('%-I:%M:%S %p')} #{marker}: #{text}\n"
      node.version += 1
      node.save!
      node
    end
  end
end
