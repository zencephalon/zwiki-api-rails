class CapturesController < ApplicationController
  # Voice memos from the Repebble Index ring, posted by the phone app as
  # multipart form data. The app's HMAC signing scheme stays undocumented, so a
  # shared token in a custom header authenticates instead.
  skip_before_action :authenticate
  before_action :verify_capture_token

  def create
    if params[:test] == 'true'
      render json: { ok: true, test: true }
      return
    end

    delivery = request.headers['X-Index-Delivery']
    if delivery.present? && Rails.cache.exist?(delivery_key(delivery))
      render json: { ok: true, duplicate: true }
      return
    end

    result = CaptureProcessor.new(user: capture_user).process(params[:transcription], at: recorded_at)
    Rails.cache.write(delivery_key(delivery), true, expires_in: 1.day) if delivery.present?

    render json: { ok: true, journal: result.journal, tasks: result.tasks.map { |t| t[:title] } }
  end

  private

  def verify_capture_token
    expected = ENV['CAPTURE_SECRET'].to_s
    given = request.headers['X-Capture-Token'].to_s
    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(given, expected)

    render json: { error: 'Bad capture token' }, status: :unauthorized
  end

  def capture_user
    User.find(ENV.fetch('CAPTURE_USER_ID', 1))
  end

  def recorded_at
    ms = params[:recordedAt].to_i
    ms.positive? ? Time.zone.at(ms / 1000.0) : Time.current
  end

  def delivery_key(delivery)
    "capture-delivery:#{delivery}"
  end
end
