# lib/json_web_token.rb
require 'jwt'

# frozen_string_literal: true
class JsonWebToken
  def self.verify(token)
    puts Rails.application.secrets.auth0_domain
    puts Rails.application.secrets.auth0_api_audience
    JWT.decode(token, nil,
               true, # Verify the signature of this token
               algorithm: 'RS256',
               iss: Rails.application.secrets.auth0_domain,
               verify_iss: true,
               aud: Rails.application.secrets.auth0_api_audience,
               verify_aud: true) do |header|
      self.jwks_hash()[header['kid']]
    end
  end

  def self.jwks_hash
    puts 'wtf ILUVU U'
    jwks_raw = Net::HTTP.get URI("#{Rails.application.secrets.auth0_domain}.well-known/jwks.json")
    puts jwks_raw
    jwks_keys = Array(JSON.parse(jwks_raw)['keys'])
    Hash[
      jwks_keys
      .map do |k|
        [
          k['kid'],
          OpenSSL::X509::Certificate.new(
            Base64.decode64(k['x5c'].first)
          ).public_key
        ]
      end
    ]
  end
end