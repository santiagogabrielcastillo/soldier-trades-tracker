# frozen_string_literal: true

require "digest"
require "openssl"
require "net/http"

module Exchanges
  # BingX Swap (perpetual futures) API client. Uses signature authentication per:
  # https://bingx-api.github.io/docs-v3/#/en/Quick%20Start/Signature%20Authentication
  class BingxClient < BaseProvider
    BASE_URL = "https://open-api.bingx.com"
    BASE_URL_TESTNET = "https://open-api-vst.bingx.com"
    SWAP_FILL_ORDERS_PATH = "/openApi/swap/v2/trade/allFillOrders"
    SWAP_V1_FULL_ORDER_PATH = "/openApi/swap/v1/trade/fullOrder"
    SWAP_USER_INCOME_PATH = "/openApi/swap/v2/user/income"

    STABLEQUOTE_SYMBOLS = %w[USDT USDC].freeze
    SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000
    V1_ORDER_LIMIT = 500
    # BingX fill/income history may be limited; fallback to this when a long range returns empty.
    FALLBACK_LOOKBACK_DAYS = 90

    def initialize(api_key:, api_secret:, base_url: nil)
      @api_key = api_key
      @api_secret = api_secret
      @base_url = base_url || BASE_URL
    end

    def fetch_my_trades(since:)
      since_ms = since.to_i * 1000
      trades = fetch_trades_from_v1_full_order(since_ms)
      trades = fetch_trades_from_v2_fills(since_ms) if trades.empty?
      trades = fetch_trades_from_income(since_ms) if trades.empty?
      # BingX fill/income history may be shorter than 6 months; retry with recent window if long range returned nothing.
      if trades.empty? && since < FALLBACK_LOOKBACK_DAYS.days.ago
        fallback_since = FALLBACK_LOOKBACK_DAYS.days.ago
        trades = fetch_my_trades(since: fallback_since)
      end
      trades
    end

    # Debug helpers (console only). v1 fullOrder needs endTime; max range 7 days.
    def debug_fetch_fills(since:, limit: 10)
      signed_get(SWAP_FILL_ORDERS_PATH, "startTime" => since.to_i * 1000, "limit" => limit)
    end

    def debug_fetch_income(since:, limit: 20)
      signed_get(SWAP_USER_INCOME_PATH, "startTime" => since.to_i * 1000, "limit" => limit)
    end

    def debug_fetch_full_order(since:, limit: 100)
      since_ms = since.to_i * 1000
      end_ms = [since_ms + SEVEN_DAYS_MS - 1, (Time.now.to_f * 1000).to_i].min
      signed_get(SWAP_V1_FULL_ORDER_PATH, "startTime" => since_ms, "endTime" => end_ms, "limit" => limit)
    end

    def debug_fetch_balance
      signed_get("/openApi/swap/v2/user/balance", {})
    end

    # Returns raw API responses from all three sources for debugging. Run in console:
    #   account = ExchangeAccount.find(...); client = Exchanges::BingxClient.new(...); client.debug_fetch_all_raw(since: 6.months.ago)
    def debug_fetch_all_raw(since:)
      since_ms = since.to_i * 1000
      end_ms = [since_ms + SEVEN_DAYS_MS - 1, (Time.now.to_f * 1000).to_i].min
      {
        v1_full_order: signed_get(SWAP_V1_FULL_ORDER_PATH, "startTime" => since_ms, "endTime" => end_ms, "limit" => 10),
        v2_fills: signed_get(SWAP_FILL_ORDERS_PATH, "startTime" => since_ms, "limit" => 10),
        income: signed_get(SWAP_USER_INCOME_PATH, "startTime" => since_ms, "limit" => 10)
      }
    end

    # Call a read-only endpoint to verify the key works. Used for key validation.
    def self.ping(api_key:, api_secret:)
      client = new(api_key: api_key, api_secret: api_secret)
      client.signed_get(SWAP_FILL_ORDERS_PATH, "startTime" => (Time.current.to_i - 86400) * 1000, "limit" => 1)
      true
    rescue => e
      Rails.logger.warn("[BingxClient] Ping failed: #{e.message}")
      false
    end

    def signed_get(path, params = {})
      if @api_secret.blank?
        raise ArgumentError, "BingX API secret is missing. Ensure the exchange account credentials are set and encryption is available in this process."
      end

      timestamp = (Time.now.to_f * 1000).to_i
      params = params.merge("timestamp" => timestamp)
      query = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
      signature = OpenSSL::HMAC.hexdigest("SHA256", @api_secret, query)

      uri = URI("#{@base_url}#{path}")
      uri.query = "#{query}&signature=#{signature}"

      req = Net::HTTP::Get.new(uri)
      req["X-BX-APIKEY"] = @api_key

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 15
      res = http.request(req)

      body = res.body.presence && JSON.parse(res.body)
      if res.code != "200"
        raise "BingX API error #{res.code}: #{body&.dig('msg') || body&.dig('code') || res.body}"
      end

      body
    rescue JSON::ParserError => e
      snippet = res.body.to_s[0..200].gsub(/\s+/, " ")
      raise "BingX API returned non-JSON response (status #{res.code}): #{snippet}. #{e.message}"
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

    def executed_at_from(raw, *time_keys)
      ms = time_keys.lazy.map { |k| raw[k] }.find(&:present?)
      ms ? Time.at(ms.to_i / 1000.0).utc : nil
    end

    def stablequote_pair?(symbol)
      return false if symbol.blank?
      quote = symbol.to_s.split("-").last.to_s.upcase
      STABLEQUOTE_SYMBOLS.include?(quote)
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
          normalized = normalize_fill_to_trade(fill, idx)
          trades << normalized if normalized && stablequote_pair?(normalized[:symbol])
        end
        break if fills.size < limit
        last_time = fills.map { |f| f["time"] || f["updateTime"] }.compact.max
        break if last_time.blank?
        start_time = last_time.to_i + 1
      end
      trades
    end

    # v1 fullOrder: ≤ 7 days per request; paginate within window by orderId when full page returned.
    def fetch_trades_from_v1_full_order(since_ms)
      trades = []
      seen_ids = []
      end_ms = (Time.now.to_f * 1000).to_i
      start_time = since_ms

      while start_time < end_ms
        window_end = [start_time + SEVEN_DAYS_MS - 1, end_ms].min
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
            normalized = normalize_v1_order_to_trade(order)
            trades << normalized if normalized && stablequote_pair?(normalized[:symbol])
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

    def normalize_v1_order_to_trade(order)
      raw = order.is_a?(Hash) ? order : order.to_h
      order_id = (raw["orderId"] || raw["order_id"])&.to_s
      return nil if order_id.blank?

      executed_at = executed_at_from(raw, "updateTime", "time")
      return nil if executed_at.blank?

      symbol = (raw["symbol"] || "").to_s
      side = (raw["side"] || raw["type"])&.to_s&.downcase

      price = (raw["avgPrice"] || raw["price"] || 0).to_d
      qty = (raw["executedQty"] || raw["executed_qty"] || raw["origQty"] || 0).to_d
      commission = (raw["commission"] || raw["fee"] || 0).to_d
      notional = price * qty
      net_amount = (side == "sell" ? notional - commission : -notional - commission)

      {
        exchange_reference_id: order_id,
        symbol: symbol,
        side: side,
        fee: commission,
        net_amount: net_amount,
        executed_at: executed_at,
        raw_payload: raw
      }
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
          normalized = normalize_income_to_trade(rec, idx)
          trades << normalized if normalized && stablequote_pair?(normalized[:symbol])
        end
        break if items.size < limit
        last_time = items.map { |r| r["time"] || r["updateTime"] }.compact.max
        break if last_time.blank?
        start_time = last_time.to_i + 1
      end
      trades
    end

    def normalize_income_to_trade(rec, index = 0)
      raw = rec.is_a?(Hash) ? rec : rec.to_h
      return nil unless (raw["incomeType"] || raw["income_type"] || "").to_s.match?(/REALIZED_PNL|TRADE|CLOSE/i)

      executed_at = executed_at_from(raw, "time", "updateTime", "createdAt")
      return nil if executed_at.blank?

      symbol = (raw["symbol"] || "").to_s
      return nil if symbol.blank?

      amount = (raw["income"] || raw["amount"] || 0).to_d
      time_ms = (raw["time"] || raw["updateTime"] || raw["createdAt"]).to_i
      api_id = raw["id"] || raw["tranId"]
      exchange_reference_id = if api_id.present?
        "income_#{time_ms}_#{index}_#{api_id}"
      else
        "income_#{Digest::SHA256.hexdigest("#{symbol}_#{time_ms}_#{index}_#{amount}")[0..15]}"
      end

      {
        exchange_reference_id: exchange_reference_id,
        symbol: symbol,
        side: "close",
        fee: 0,
        net_amount: amount,
        executed_at: executed_at,
        raw_payload: raw
      }
    end

    def normalize_fill_to_trade(fill, index = 0)
      raw = fill.is_a?(Hash) ? fill : fill.to_h
      order_id = (raw["orderId"] || raw["order_id"])&.to_s
      return nil if order_id.blank?

      executed_at = executed_at_from(raw, "time", "updateTime", "createdAt", "update_time")
      return nil if executed_at.blank?

      symbol = (raw["symbol"] || "").to_s
      side = (raw["side"] || raw["type"])&.to_s&.downcase

      price = (raw["avgPrice"] || raw["price"] || 0).to_d
      qty = (raw["fillQty"] || raw["filledQty"] || raw["executedQty"] || raw["qty"] || 0).to_d
      commission = (raw["commission"] || raw["fee"] || 0).to_d
      notional = price * qty
      net_amount = (side == "sell" ? notional - commission : -notional - commission)

      fill_id = (raw["tradeId"] || raw["fillId"]).to_s.presence
      ts_ms = (raw["time"] || raw["updateTime"] || raw["createdAt"] || raw["update_time"]).to_i
      exchange_reference_id = fill_id.presence || "#{order_id}_#{ts_ms}_#{index}"

      {
        exchange_reference_id: exchange_reference_id,
        symbol: symbol,
        side: side,
        fee: commission,
        net_amount: net_amount,
        executed_at: executed_at,
        raw_payload: raw
      }
    end
  end
end
