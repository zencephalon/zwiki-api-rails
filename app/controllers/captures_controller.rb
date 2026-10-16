class CapturesController < ApplicationController
  # Temporary probe: logs whatever the Repebble webhook sends so we can learn
  # its payload and signature format before building real routing.
  skip_before_action :authenticate

  MAX_BODY_LOG = 10_000

  def create
    headers = request.headers.env
      .select { |k, _| k.start_with?('HTTP_') || %w[CONTENT_TYPE CONTENT_LENGTH].include?(k) }
      .transform_keys { |k| k.delete_prefix('HTTP_') }
    body = request.raw_post.to_s

    Rails.logger.info("[capture] headers=#{headers.to_json}")
    Rails.logger.info("[capture] body(#{body.bytesize}b)=#{body.byteslice(0, MAX_BODY_LOG)}")

    head :ok
  end
end
