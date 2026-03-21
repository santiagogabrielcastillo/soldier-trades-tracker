# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Stocks
  # Fetches CEDEAR/stock quotes from InvertirOnline (IOL) API.
  # Auth: POST /token with username+password → bearer token (15 min validity).
  # Token is cached class-wide for 14 minutes to avoid re-auth on every quote call.
  # Credentials: IOL_USERNAME / IOL_PASSWORD env vars or Rails credentials [:iol][:username/:password].
  class IolClient
    TOKEN_URL = "https://api.invertironline.com/token"
    BASE_URL  = "https://api.invertironline.com/api/v2"
    MARKET    = "bCBA"

    @token_cache = nil
    @token_mutex = Mutex.new

    class << self
      attr_accessor :token_cache, :token_mutex

      def credentials
        username = ENV["IOL_USERNAME"].presence ||
                   Rails.application.credentials.dig(:iol, :username).presence
        password = ENV["IOL_PASSWORD"].presence ||
                   Rails.application.credentials.dig(:iol, :password).presence
        return nil if username.blank? || password.blank?

        { username: username, password: password }
      end
    end

    # Returns BigDecimal ARS price or nil — never raises.
    def quote(ticker)
      token = fetch_token
      return nil if token.blank?

      uri = URI("#{BASE_URL}/#{MARKET}/Titulos/#{URI.encode_uri_component(ticker)}/Cotizacion")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      price = data["ultimoPrecio"]&.to_d
      price&.positive? ? price : nil
    rescue => e
      Rails.logger.error("[Stocks::IolClient] quote(#{ticker}) error: #{e.message}")
      nil
    end

    private

    def fetch_token
      # Mutex prevents multiple threads from authenticating simultaneously
      self.class.token_mutex.synchronize do
        cached = self.class.token_cache
        return cached[:token] if cached && cached[:expires_at] > Time.current

        creds = self.class.credentials
        return nil if creds.nil?

        response = Net::HTTP.post(
          URI(TOKEN_URL),
          URI.encode_www_form(username: creds[:username], password: creds[:password], grant_type: "password"),
          "Content-Type" => "application/x-www-form-urlencoded"
        )
        return nil unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        token = data["access_token"]
        return nil if token.blank?

        # Cache for 14 min — token is valid for 15 min per IOL docs
        self.class.token_cache = { token: token, expires_at: Time.current + 14.minutes }
        token
      end
    rescue => e
      Rails.logger.error("[Stocks::IolClient] token fetch error: #{e.message}")
      nil
    end
  end
end
