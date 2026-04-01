# frozen_string_literal: true

module Exchanges
  # BingX Swap (perpetual futures) API client. Uses Bingx::HttpClient for signed requests
  # and Bingx::TradeNormalizer for payloads. See: https://bingx-api.github.io/docs-v3/
  class BingxClient < BaseProvider
    BASE_URL = "https://open-api.bingx.com"
    SWAP_FILL_ORDERS_PATH = "/openApi/swap/v2/trade/allFillOrders"
    SWAP_V1_FULL_ORDER_PATH = "/openApi/swap/v1/trade/fullOrder"
    SWAP_USER_INCOME_PATH = "/openApi/swap/v2/user/income"

    DEFAULT_QUOTE_CURRENCIES = Exchanges::QuoteCurrencies::DEFAULT
    SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000
    V1_ORDER_LIMIT = 500
    FALLBACK_LOOKBACK_DAYS = 90

    def initialize(api_key:, api_secret:, base_url: nil, allowed_quote_currencies: DEFAULT_QUOTE_CURRENCIES)
      @allowed_quote_currencies = allowed_quote_currencies.presence || DEFAULT_QUOTE_CURRENCIES
      @http = Bingx::HttpClient.new(
        api_key: api_key,
        api_secret: api_secret,
        base_url: base_url || BASE_URL
      )
    end

    def fetch_my_trades(since:)
      since_ms = since.to_i * 1000
      trades = fetch_trades_from_v1_full_order(since_ms)
      trades = fetch_trades_from_v2_fills(since_ms) if trades.empty?
      trades = fetch_trades_from_income(since_ms) if trades.empty?
      if trades.empty? && since < FALLBACK_LOOKBACK_DAYS.days.ago
        trades = fetch_my_trades(since: FALLBACK_LOOKBACK_DAYS.days.ago)
      end
      trades
    end

    def self.ping(api_key:, api_secret:)
      client = new(api_key: api_key, api_secret: api_secret)
      client.signed_get(SWAP_FILL_ORDERS_PATH, "startTime" => 1.day.ago.to_i * 1000, "limit" => 1)
      true
    rescue => e
      Rails.logger.warn("[BingxClient] Ping failed: #{e.message}")
      false
    end

    # Delegates to HttpClient. Public so tests can stub Net::HTTP and assert ApiError behavior.
    def signed_get(path, params = {})
      @http.get(path, params)
    end

    private

    def ok_response?(resp)
      return false unless resp.is_a?(Hash)
      c = resp["code"]
      c.nil? || c == 0 || c == "0"
    end

    def extract_list(data, *keys)
      return [] if data.blank?
      return data if data.is_a?(Array)
      keys.each { |k| return data[k] if data[k].present? && data[k].is_a?(Array) }
      []
    end

    # Returns true when the symbol's quote currency is in the per-account whitelist.
    # Symbol must be in app format (BASE-QUOTE, e.g. "BTC-USDC"). Fails closed (returns false)
    # on a blank whitelist as a safeguard; the constructor always ensures a non-blank value.
    def allowed_quote?(symbol)
      return false if @allowed_quote_currencies.blank?
      return false if symbol.blank?
      quote = symbol.to_s.split("-").last.to_s.upcase
      @allowed_quote_currencies.include?(quote)
    end

    def fetch_trades_from_v2_fills(since_ms, limit: 100)
      trades = []
      start_time = since_ms
      loop do
        resp = signed_get(SWAP_FILL_ORDERS_PATH, "startTime" => start_time, "limit" => limit)
        break unless ok_response?(resp)
        fills = extract_list(resp["data"], "fill_orders", "fills", "orders", "order")
        break if fills.empty?
        fills.each_with_index do |fill, idx|
          normalized = Bingx::TradeNormalizer.normalize_fill_to_trade(fill, idx)
          trades << normalized if normalized && allowed_quote?(normalized[:symbol])
        end
        break if fills.size < limit
        last_time = fills.map { |f| f["time"] || f["updateTime"] }.compact.max
        break if last_time.blank?
        start_time = last_time.to_i + 1
      end
      trades
    end

    def fetch_trades_from_v1_full_order(since_ms)
      trades = []
      seen_ids = Set.new
      end_ms = (Time.now.to_f * 1000).to_i
      start_time = since_ms

      while start_time < end_ms
        window_end = [ start_time + SEVEN_DAYS_MS - 1, end_ms ].min
        window_order_id = nil

        loop do
          params = { "startTime" => start_time, "endTime" => window_end, "limit" => V1_ORDER_LIMIT }
          params["orderId"] = window_order_id if window_order_id
          resp = signed_get(SWAP_V1_FULL_ORDER_PATH, params)
          break unless ok_response?(resp)
          orders = resp.dig("data", "orders") || []
          break if orders.empty?

          orders.each do |order|
            next unless order["status"] == "FILLED"
            order_id = (order["orderId"] || order["order_id"])&.to_s
            next if order_id.blank? || seen_ids.include?(order_id)
            seen_ids << order_id
            normalized = Bingx::TradeNormalizer.normalize_v1_order_to_trade(order)
            trades << normalized if normalized && allowed_quote?(normalized[:symbol])
          end

          break if orders.size < V1_ORDER_LIMIT
          min_order_id = orders.map { |o| o["orderId"] || o["order_id"] }.compact.min
          break if min_order_id.nil?
          window_order_id = min_order_id
        end

        start_time = window_end + 1
      end

      trades.sort_by { |t| t[:executed_at] }
    end

    def fetch_trades_from_income(since_ms, limit: 100)
      trades = []
      start_time = since_ms
      loop do
        resp = signed_get(SWAP_USER_INCOME_PATH, "startTime" => start_time, "limit" => limit)
        break unless ok_response?(resp)
        items = extract_list(resp["data"], "income", "incomes", "data")
        break if items.empty?
        items.each_with_index do |rec, idx|
          normalized = Bingx::TradeNormalizer.normalize_income_to_trade(rec, idx)
          trades << normalized if normalized && allowed_quote?(normalized[:symbol])
        end
        break if items.size < limit
        last_time = items.map { |r| r["time"] || r["updateTime"] }.compact.max
        break if last_time.blank?
        start_time = last_time.to_i + 1
      end
      trades
    end
  end
end
