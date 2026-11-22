class CaptureProcessor
  def initialize(user:, router: CaptureRouter.new, inbox: TreedoInbox.new)
    @user = user
    @router = router
    @inbox = inbox
  end

  def process(text, at: Time.current)
    result = @router.route(text)
    Rails.logger.info("[capture] routed journal=#{result.journal.present?} tasks=#{result.tasks.map { |t| t[:title] }.to_json}")
    result.tasks.each { |task| @inbox.add(task[:title], task[:notes], today: task[:today]) }
    DailyJournal.new(@user).append(result.journal, marker: '🎤', at: at) if result.journal.present?
    result
  end
end
