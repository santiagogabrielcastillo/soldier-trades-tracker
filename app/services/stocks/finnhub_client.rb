# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Stocks
  class FinnhubClient
    BASE_URL = "https://finnhub.io/api/v1"

    def initialize(api_key:)
      @api_key = api_key
    end

    def quote(ticker)
      return nil if @api_key.blank?

      uri = URI("#{BASE_URL}/quote")
      uri.query = URI.encode_www_form(symbol: ticker, token: @api_key)
      response = Net::HTTP.get_response(uri)
      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      price = data["c"]&.to_d
      price&.positive? ? price : nil
    rescue => e
      Rails.logger.error("[Stocks::FinnhubClient] Error fetching quote for #{ticker}: #{e.message}")
      nil
    end
  end
end
