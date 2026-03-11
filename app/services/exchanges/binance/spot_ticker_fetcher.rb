# frozen_string_literal: true

require "net/http"

module Exchanges
  module Binance
    # Fetches current price for Spot symbols via Binance public API (no authentication).
    # Uses batch endpoint: GET /api/v3/ticker/price?symbols=["LDOUSDT","AVAXUSDT"] (weight 4).
    # Used for spot portfolio unrealized PnL.
    class SpotTickerFetcher
      BASE_URL = "https://api.binance.com"
      TICKER_PRICE_PATH = "/api/v3/ticker/price"
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10

      # @param tokens [Array<String>] list of token symbols (e.g. ["LDO", "AVAX"])
      # @return [Hash<String, BigDecimal>] token => price; only includes tokens that succeeded
      def self.fetch_prices(tokens:)
        new.fetch_prices(tokens: tokens)
      end

      def fetch_prices(tokens:)
        return {} if tokens.blank?
        tokens = tokens.uniq.map { |t| t.to_s.strip.upcase }.reject(&:blank?)
        return {} if tokens.empty?
        symbols = tokens.map { |t| "#{t}USDT" }
        uri = URI("#{BASE_URL}#{TICKER_PRICE_PATH}")
        uri.query = URI.encode_www_form("symbols" => symbols.to_json)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        req = Net::HTTP::Get.new(uri)
        res = http.request(req)
        unless res.code.to_s == "200"
          Rails.logger.warn("[Binance::SpotTickerFetcher] HTTP #{res.code}: #{res.body.to_s[0..200]}")
          return {}
        end
        data = JSON.parse(res.body)
        data = [data] unless data.is_a?(Array)
        result = {}
        data.each do |item|
          symbol = item["symbol"].to_s
          token = symbol.sub(/\A(.+)USDT\z/i, "\\1")
          price = extract_price(item)
          result[token] = price if token.present? && price.present?
        end
        result
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        Rails.logger.warn("[Binance::SpotTickerFetcher] Timeout: #{e.message}")
        {}
      rescue JSON::ParserError => e
        Rails.logger.warn("[Binance::SpotTickerFetcher] Parse error: #{e.message}")
        {}
      rescue StandardError => e
        Rails.logger.warn("[Binance::SpotTickerFetcher] Error: #{e.class} #{e.message}")
        {}
      end

      private

      def extract_price(item)
        return nil if item.blank?
        val = item["price"].to_s.strip
        return nil if val.blank?
        parsed = val.to_d
        parsed.positive? ? parsed : nil
      end
    end
  end
end
