# frozen_string_literal: true

require "net/http"

module Exchanges
  module Binance
    # Fetches current mark price for USDⓈ-M Futures symbols via Binance public API (no authentication).
    # Used to compute unrealized PnL/ROI for open positions on the trades index.
    # One GET per symbol; timeouts 5s open / 10s read; on failure returns nil for that symbol and continues.
    class TickerFetcher
      BASE_URL = "https://fapi.binance.com"
      PREMIUM_INDEX_PATH = "/fapi/v1/premiumIndex"
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10

      # @param symbols [Array<String>] list of symbols in app form (e.g. ["BTC-USDT", "ETH-USDT"])
      # @return [Hash<String, BigDecimal>] symbol => price; only includes symbols that succeeded
      def self.fetch_prices(symbols:)
        new.fetch_prices(symbols: symbols)
      end

      def fetch_prices(symbols:)
        return {} if symbols.blank?
        symbols = symbols.uniq
        result = {}
        symbols.each do |symbol|
          price = fetch_one(symbol)
          result[symbol] = price if price.present?
        end
        result
      end

      private

      def fetch_one(symbol)
        binance_symbol = symbol.to_s.gsub("-", "")
        uri = URI("#{BASE_URL}#{PREMIUM_INDEX_PATH}")
        uri.query = URI.encode_www_form("symbol" => binance_symbol)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        req = Net::HTTP::Get.new(uri)
        res = http.request(req)
        unless res.code.to_s == "200"
          Rails.logger.warn("[Binance::TickerFetcher] HTTP #{res.code} for #{symbol}: #{res.body.to_s[0..200]}")
          return nil
        end
        data = JSON.parse(res.body)
        extract_mark_price(data)
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        Rails.logger.warn("[Binance::TickerFetcher] Timeout for #{symbol}: #{e.message}")
        nil
      rescue JSON::ParserError => e
        Rails.logger.warn("[Binance::TickerFetcher] Parse error for #{symbol}: #{e.message}")
        nil
      rescue StandardError => e
        Rails.logger.warn("[Binance::TickerFetcher] Error for #{symbol}: #{e.class} #{e.message}")
        nil
      end

      def extract_mark_price(data)
        return nil if data.blank?
        val = data["markPrice"] || data["mark_price"]
        return nil if val.blank?
        parsed = val.to_s.strip.to_d
        parsed.positive? ? parsed : nil
      end
    end
  end
end
