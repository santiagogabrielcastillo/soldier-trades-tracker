# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Stocks
  # Fetches real-time stock quotes from Finnhub (https://finnhub.io).
  # Free tier: 60 requests/min. Requires FINNHUB_API_KEY env var or
  # Rails.application.credentials.finnhub.api_key.
  class FinnhubClient
    BASE_URL = "https://finnhub.io/api/v1"

    def quote(ticker)
      key = api_key
      return nil if key.blank?

      uri = URI("#{BASE_URL}/quote")
      uri.query = URI.encode_www_form(symbol: ticker, token: key)
      response = Net::HTTP.get_response(uri)
      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      price = data["c"]&.to_d
      price&.positive? ? price : nil
    rescue => e
      Rails.logger.error("[Stocks::FinnhubClient] Error fetching quote for #{ticker}: #{e.message}")
      nil
    end

    private

    def api_key
      ENV["FINNHUB_API_KEY"].presence || Rails.application.credentials.dig(:finnhub, :api_key).presence
    end
  end
end
