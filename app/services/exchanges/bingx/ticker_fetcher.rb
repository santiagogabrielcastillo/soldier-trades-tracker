# frozen_string_literal: true

require "net/http"

module Exchanges
  module Bingx
    # Fetches current price for swap symbols via BingX public ticker API (no authentication).
    # Used to compute unrealized PnL/ROI for open positions on the trades index.
    # One GET per symbol; timeouts 5s open / 10s read; on failure returns nil for that symbol and continues.
    class TickerFetcher
      BASE_URL = "https://open-api.bingx.com"
      TICKER_PATH = "/openApi/swap/v2/quote/ticker"
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10

      # @param symbols [Array<String>] list of symbols (e.g. ["BTC-USDT", "ETH-USDT"])
      # @return [Hash<String, BigDecimal]] symbol => price; only includes symbols that succeeded
      def self.fetch_prices(symbols:)
        new.fetch_prices(symbols: symbols)
      end

      def fetch_prices(symbols:)
        return {} if symbols.blank?
        symbols = symbols.uniq
        result = {}
        # Serial requests; acceptable for typical N (e.g. <10 open symbols). For many symbols, consider batching or parallel requests in a follow-up.
        symbols.each do |symbol|
          price = fetch_one(symbol)
          result[symbol] = price if price.present?
        end
        result
      end

      private

      def fetch_one(symbol)
        uri = URI("#{BASE_URL}#{TICKER_PATH}")
        uri.query = URI.encode_www_form("symbol" => symbol)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        req = Net::HTTP::Get.new(uri)
        res = http.request(req)
        unless res.code.to_s == "200"
          Rails.logger.warn("[TickerFetcher] HTTP #{res.code} for #{symbol}: #{res.body.to_s[0..200]}")
          return nil
        end
        data = JSON.parse(res.body)
        extract_price_from_ticker_response(data)
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        Rails.logger.warn("[TickerFetcher] Timeout for #{symbol}: #{e.message}")
        nil
      rescue JSON::ParserError => e
        Rails.logger.warn("[TickerFetcher] Parse error for #{symbol}: #{e.message}")
        nil
      rescue StandardError => e
        Rails.logger.warn("[TickerFetcher] Error for #{symbol}: #{e.class} #{e.message}")
        nil
      end

      # BingX ticker response may have price in "data" with lastPrice or price. Isolated for API changes.
      def extract_price_from_ticker_response(data)
        return nil if data.blank?
        payload = data.is_a?(Hash) ? data["data"] : nil
        payload = data if payload.blank? && data.is_a?(Hash)
        return nil if payload.blank?
        val = payload["lastPrice"] || payload["last_price"] || payload["price"]
        return nil if val.blank?
        num = val.to_s.strip
        return nil if num.empty?
        parsed = num.to_d
        parsed.positive? ? parsed : nil
      end
    end
  end
end
