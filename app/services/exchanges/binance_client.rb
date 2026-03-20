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

    DEFAULT_QUOTE_CURRENCIES = Exchanges::QuoteCurrencies::DEFAULT

    SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000
    USER_TRADES_LIMIT = 1000
    INCOME_LIMIT = 1000
    # Binance userTrades only returns last 6 months; use same window for income-based symbol discovery.
    INCOME_LOOKBACK_MS = 6 * 31 * 24 * 60 * 60 * 1000

    def initialize(api_key:, api_secret:, base_url: nil, allowed_quote_currencies: DEFAULT_QUOTE_CURRENCIES)
      @allowed_quote_currencies = allowed_quote_currencies.presence || DEFAULT_QUOTE_CURRENCIES
      @http = Binance::HttpClient.new(
        api_key: api_key,
        api_secret: api_secret,
        base_url: base_url.presence || BASE_URL
      )
    end

    # Fetches all userTrades from Binance: discovers symbols (positionRisk + income), filters by
    # allowed_quote_currencies to avoid unnecessary API calls, requests 7-day windows per symbol
    # (API limit), normalizes, dedupes by exchange_reference_id, sorts by executed_at.
    # Note: discover_symbols (income pagination) is unfiltered — the whitelist only prevents
    # userTrades API calls for excluded symbols, not the discovery calls themselves.
    def fetch_my_trades(since:)
      since_ms = time_to_ms(since)
      symbols = discover_symbols(since_ms)
      return [] if symbols.empty?

      all_trades = []
      symbols.each do |raw_symbol|
        # Normalize to app format (e.g. BTCUSDC → BTC-USDC) to check quote currency before fetching.
        normalized = Binance::TradeNormalizer.normalize_symbol(raw_symbol)
        next unless allowed_quote?(normalized)
        all_trades.concat(fetch_user_trades_for_symbol(raw_symbol, since_ms))
      end

      all_trades.uniq { |t| t[:exchange_reference_id] }.sort_by { |t| t[:executed_at] }
    end

    def self.ping(api_key:, api_secret:)
      client = new(api_key: api_key, api_secret: api_secret)
      resp = client.signed_get(POSITION_RISK_PATH, {})
      check_binance_error!(resp)
      true
    rescue ApiError, StandardError => e
      Rails.logger.warn("[BinanceClient] Ping failed: #{e.message}")
      false
    end

    def signed_get(path, params = {})
      @http.get(path, params)
    end

    # Returns Hash[app_symbol => leverage (Integer)]. Uses positionRisk; symbols normalized to app form (e.g. BTC-USDT).
    # userTrades does not return leverage, so the index uses this to show leverage/margin/ROI for Binance positions.
    def leverage_by_symbol
      resp = signed_get(POSITION_RISK_PATH, {})
      self.class.check_binance_error!(resp)
      return {} unless resp.is_a?(Array)

      resp.each_with_object({}) do |pos, out|
        sym = (pos["symbol"] || pos["symbol_name"])&.to_s&.strip
        next if sym.blank?
        app_sym = Binance::TradeNormalizer.normalize_symbol(sym)
        next if app_sym.blank?
        lev = (pos["leverage"] || pos["leverage_value"]).to_s.strip
        next if lev.blank?
        n = lev.to_i
        out[app_sym] = n if n.positive?
      end
    end

    private

    # Returns true when the symbol's quote currency is in the per-account whitelist.
    # Symbol must be in app format (BASE-QUOTE, e.g. "BTC-USDC"). Fails closed (returns false)
    # on a blank whitelist as a safeguard; the constructor always ensures a non-blank value.
    def allowed_quote?(symbol)
      return false if @allowed_quote_currencies.blank?
      return false if symbol.blank?
      quote = symbol.to_s.split("-").last.to_s.upcase
      @allowed_quote_currencies.include?(quote)
    end

    def discover_symbols(since_ms)
      from_positions = symbols_from_position_risk
      from_income = symbols_from_income(since_ms)
      (from_positions + from_income).uniq
    end

    def symbols_from_position_risk
      resp = signed_get(POSITION_RISK_PATH, {})
      check_binance_error!(resp)
      return [] unless resp.is_a?(Array)

      resp.filter_map do |pos|
        amt = (pos["positionAmt"] || pos["position_amt"] || 0).to_d
        next if amt.zero?
        pos["symbol"]&.to_s&.strip
      end.uniq
    end

    # Paginate income (max 1000 per call) so we don't miss symbols when there are many REALIZED_PNL records.
    def symbols_from_income(since_ms)
      end_ms = (Time.now.to_f * 1000).to_i
      start_ms = [ since_ms, end_ms - INCOME_LOOKBACK_MS ].min
      symbols = []
      loop do
        resp = signed_get(INCOME_PATH, "incomeType" => "REALIZED_PNL", "startTime" => start_ms, "endTime" => end_ms, "limit" => INCOME_LIMIT)
        check_binance_error!(resp)
        break unless resp.is_a?(Array)

        resp.each do |rec|
          s = rec["symbol"]&.to_s&.strip
          symbols << s if s.present?
        end
        break if resp.size < INCOME_LIMIT
        last_time = resp.last&.dig("time") || resp.last&.dig("timestamp")
        break if last_time.nil?
        start_ms = last_time.to_i + 1
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
        check_binance_error!(resp)
        list = extract_trades_list(resp)
        list.each do |raw|
          normalized = Binance::TradeNormalizer.user_trade_to_hash(raw)
          trades << normalized if normalized
        end

        if list.size >= USER_TRADES_LIMIT
          # Full page: may be more in this window; paginate by moving startTime past last trade
          last_time = list.last&.dig("time") || list.last&.dig("timestamp")
          last_time ? start_time = last_time.to_i + 1 : start_time = window_end + 1
        else
          # No more in this window; advance to next 7-day window
          start_time = window_end + 1
        end
      end

      trades
    end

    def time_to_ms(time)
      time.to_i * 1000
    end

    # userTrades returns an array; some wrappers return { "trades" => [...] }.
    def extract_trades_list(resp)
      return resp if resp.is_a?(Array)
      return resp["trades"] if resp.is_a?(Hash) && resp["trades"].is_a?(Array)
      []
    end

    # Binance can return HTTP 200 with body {"code": -2015, "msg": "Invalid API key"}.
    # Raise ApiError so the job retries and we don't report "success with 0 trades".
    def self.check_binance_error!(resp)
      return unless resp.is_a?(Hash)
      code = resp["code"]
      return if code.nil? || code.to_i == 0
      msg = resp["msg"] || resp["message"] || "Binance API error"
      raise ApiError, "Binance API error (code #{code}): #{msg}"
    end

    def check_binance_error!(resp)
      self.class.check_binance_error!(resp)
    end
  end
end
