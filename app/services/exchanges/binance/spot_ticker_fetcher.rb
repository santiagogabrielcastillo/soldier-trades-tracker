# frozen_string_literal: true

require "net/http"

module Exchanges
  module Binance
    # Fetches current price for Spot tokens via Binance public Futures API (no authentication).
    # Uses /fapi/v1/ticker/price?symbol=XXXUSDT — one request per token.
    # fapi.binance.com is used because api.binance.com (Spot domain) is geo-blocked on some
    # cloud providers (e.g. Railway/AWS). The Futures ticker price is equivalent for major tokens.
    # Note: fapi does NOT support the `symbols` batch parameter (Spot API feature); individual
    # requests per token are used instead.
    class SpotTickerFetcher
      BASE_URL = "https://fapi.binance.com"
      TICKER_PRICE_PATH = "/fapi/v1/ticker/price"
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

        result = {}
        tokens.each do |token|
          price = fetch_one(token)
          result[token] = price if price.present?
        end
        result
      end

      private

      def fetch_one(token)
        symbol = "#{token}USDT"
        uri = URI("#{BASE_URL}#{TICKER_PRICE_PATH}")
        uri.query = URI.encode_www_form("symbol" => symbol)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        req = Net::HTTP::Get.new(uri)
        res = http.request(req)
        unless res.code.to_s == "200"
          Rails.logger.warn("[Binance::SpotTickerFetcher] HTTP #{res.code} for #{token}: #{res.body.to_s[0..200]}")
          return nil
        end
        data = JSON.parse(res.body)
        extract_price(data)
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        Rails.logger.warn("[Binance::SpotTickerFetcher] Timeout for #{token}: #{e.message}")
        nil
      rescue JSON::ParserError => e
        Rails.logger.warn("[Binance::SpotTickerFetcher] Parse error for #{token}: #{e.message}")
        nil
      rescue StandardError => e
        Rails.logger.warn("[Binance::SpotTickerFetcher] Error for #{token}: #{e.class} #{e.message}")
        nil
      end

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
