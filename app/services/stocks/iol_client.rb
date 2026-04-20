# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "digest"

module Stocks
  # Fetches CEDEAR/stock quotes from InvertirOnline (IOL) API.
  # Auth: POST /token with username+password → bearer token (15 min validity).
  # Token is cached in Rails.cache per credential pair for 14 minutes.
  class IolClient
    TOKEN_URL = "https://api.invertironline.com/token"
    BASE_URL  = "https://api.invertironline.com/api/v2"
    MARKET    = "bCBA"

    def initialize(username:, password:)
      @username = username
      @password = password
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
      cache_key = "iol_token:#{Digest::SHA256.hexdigest("#{@username}:#{@password}")}"
      Rails.cache.fetch(cache_key, expires_in: 14.minutes) do
        response = Net::HTTP.post(
          URI(TOKEN_URL),
          URI.encode_www_form(username: @username, password: @password, grant_type: "password"),
          "Content-Type" => "application/x-www-form-urlencoded"
        )
        return nil unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        data["access_token"].presence
      end
    rescue => e
      Rails.logger.error("[Stocks::IolClient] token fetch error: #{e.message}")
      nil
    end
  end
end
