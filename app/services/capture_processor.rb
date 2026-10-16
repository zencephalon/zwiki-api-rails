class CaptureProcessor
  TIME_ZONE = ENV.fetch('CAPTURE_TIME_ZONE', 'America/New_York')

  def initialize(user:, router: CaptureRouter.new)
    @user = user
    @router = router
  end

  def process(text, at: Time.current)
    result = @router.route(text)
    Rails.logger.info("[capture] routed journal=#{result.journal.present?} tasks=#{result.tasks.map { |t| t[:title] }.to_json}")
    append_to_journal(result.journal, at) if result.journal.present?
    result.tasks.each { |task| ThingsMailer.task(task[:title], task[:notes]).deliver_now }
    result
  end

  private

  def append_to_journal(text, at)
    now = at.in_time_zone(TIME_ZONE)
    # Matches zwiki's getDateStamp(): "Fri Oct 16 2026".
    name = now.strftime('%a %b %d %Y')
    node = @user.nodes.find_by(name: name) || @user.nodes.new(name: name).tap(&:fill_default_content)

    node.content = "#{node.content.rstrip}\n\n#{now.strftime('%-I:%M:%S %p')} 🎤: #{text}\n"
    node.version += 1
    node.save!
  end
end
