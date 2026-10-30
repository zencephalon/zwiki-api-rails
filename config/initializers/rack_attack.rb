class Rack::Attack

  # `Rack::Attack` is configured to use the `Rails.cache` value by default,
  # but you can override that by setting the `Rack::Attack.cache.store` value
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # Allow all local traffic
#  whitelist('allow-localhost') do |req|
#    '127.0.0.1' == req.ip || '::1' == req.ip
#  end

  # zencephalon's build renders ~17 pages/s from one IP. A throttled fetch there
  # used to get cached as a permanent 404, so authenticated callers skip the limit.
  safelist('authenticated') do |req|
    token = req.get_header('HTTP_AUTHORIZATION')
    token.present? && (ApiToken.active.exists?(token: token) || User.exists?(api_key: token))
  end

  # Allow an IP address to make 20 requests every 5 seconds
  throttle('req/ip', limit: 20, period: 5) do |req|
    req.ip
  end

  # Send the following response to throttled clients
  self.throttled_response = ->(env) {
    retry_after = (env['rack.attack.match_data'] || {})[:period]
    [
      429,
      {'Content-Type' => 'application/json', 'Retry-After' => retry_after.to_s},
      [{error: "Throttle limit reached. Retry later."}.to_json]
    ]
  }
end
