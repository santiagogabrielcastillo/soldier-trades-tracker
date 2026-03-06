# frozen_string_literal: true

module Exchanges
  # Binance USDⓈ-M Futures API client. Uses Binance::HttpClient for signed requests
  # and Binance::TradeNormalizer for userTrades payloads.
  # Symbol discovery: positionRisk (open positions) then income (REALIZED_PNL) fallback.
  # userTrades requires symbol; max 7-day window per request. Supports testnet via base_url.
  class BinanceClient < BaseProvider
    BASE_URL = "https://fapi.binance.com"
    BASE_URL_TESTNET = "https://testnet.binancefuture.com"
    POSITION_RISK_PATH = "/fapi/v2/positionRisk"
    INCOME_PATH = "/fapi/v1/income"
    USER_TRADES_PATH = "/fapi/v1/userTrades"

    SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000
    USER_TRADES_LIMIT = 1000
    INCOME_LIMIT = 1000

    def initialize(api_key:, api_secret:, base_url: nil)
      @http = Binance::HttpClient.new(
        api_key: api_key,
        api_secret: api_secret,
        base_url: base_url.presence || BASE_URL
      )
    end

    def fetch_my_trades(since:)
      since_ms = since.to_i * 1000
      symbols = discover_symbols(since_ms)
      return [] if symbols.empty?

      all_trades = []
      symbols.each do |symbol|
        all_trades.concat(fetch_user_trades_for_symbol(symbol, since_ms))
      end

      all_trades.uniq { |t| t[:exchange_reference_id] }.sort_by { |t| t[:executed_at] }
    end

    def self.ping(api_key:, api_secret:)
      client = new(api_key: api_key, api_secret: api_secret)
      client.signed_get(POSITION_RISK_PATH, {})
      true
    rescue ApiError, StandardError => e
      Rails.logger.warn("[BinanceClient] Ping failed: #{e.message}")
      false
    end

    def signed_get(path, params = {})
      @http.get(path, params)
    end

    private

    def discover_symbols(since_ms)
      symbols = symbols_from_position_risk
      return symbols if symbols.any?

      symbols_from_income(since_ms)
    end

    def symbols_from_position_risk
      resp = signed_get(POSITION_RISK_PATH, {})
      return [] unless resp.is_a?(Array)

      resp.filter_map do |pos|
        amt = (pos["positionAmt"] || pos["position_amt"] || 0).to_d
        next if amt.zero?
        pos["symbol"]&.to_s&.strip
      end.uniq
    end

    def symbols_from_income(since_ms)
      end_ms = (Time.now.to_f * 1000).to_i
      symbols = []
      # One or two chunks: full range or split; income returns max 1000 per call
      resp = signed_get(INCOME_PATH, "incomeType" => "REALIZED_PNL", "startTime" => since_ms, "endTime" => end_ms, "limit" => INCOME_LIMIT)
      return [] unless resp.is_a?(Array)

      resp.each do |rec|
        s = rec["symbol"]&.to_s&.strip
        symbols << s if s.present?
      end
      symbols.uniq
    end

    def fetch_user_trades_for_symbol(symbol, since_ms)
      trades = []
      end_ms = (Time.now.to_f * 1000).to_i
      start_time = since_ms

      while start_time < end_ms
        window_end = [ start_time + SEVEN_DAYS_MS - 1, end_ms ].min
        resp = signed_get(USER_TRADES_PATH, "symbol" => symbol, "startTime" => start_time, "endTime" => window_end, "limit" => USER_TRADES_LIMIT)
        break unless resp.is_a?(Array)

        resp.each do |raw|
          normalized = Binance::TradeNormalizer.user_trade_to_hash(raw)
          trades << normalized if normalized
        end

        break if resp.size < USER_TRADES_LIMIT
        start_time = window_end + 1
      end

      trades
    end
  end
end
