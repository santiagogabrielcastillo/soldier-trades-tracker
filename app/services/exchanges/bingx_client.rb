# frozen_string_literal: true

require "openssl"
require "net/http"

module Exchanges
  # BingX Spot API client. Uses signature authentication per:
  # https://bingx-api.github.io/docs-v3/#/en/Quick%20Start/Signature%20Authentication
  class BingxClient < BaseProvider
    BASE_URL = "https://open-api.bingx.com"
    SPOT_ORDER_HISTORY_PATH = "/openApi/spot/v1/order/history"

    STABLEQUOTE_SYMBOLS = %w[USDT USDC].freeze

    def initialize(api_key:, api_secret:)
      @api_key = api_key
      @api_secret = api_secret
    end

    def fetch_my_trades(since:)
      since_ms = since.to_i * 1000
      all_trades = []
      page_index = 1
      page_size = 100

      loop do
        params = {
          "startTime" => since_ms,
          "pageIndex" => page_index,
          "pageSize" => page_size,
          "status" => "FILLED"
        }
        resp = signed_get(SPOT_ORDER_HISTORY_PATH, params)
        break unless resp.is_a?(Hash)
        break if resp["code"] && resp["code"] != 0

        data = resp["data"]
        break if data.blank?

        orders = data.is_a?(Array) ? data : (data["orders"] || data["order"] || [])
        break if orders.empty?

        orders.each do |order|
          normalized = normalize_order_to_trade(order)
          all_trades << normalized if normalized && stablequote_pair?(normalized[:symbol])
        end

        break if orders.size < page_size
        page_index += 1
      end

      all_trades
    end

    # Call a read-only endpoint to verify the key works. Used for key validation.
    def self.ping(api_key:, api_secret:)
      client = new(api_key: api_key, api_secret: api_secret)
      # Query order history with a high startTime (no data) to avoid affecting anything
      client.signed_get(SPOT_ORDER_HISTORY_PATH, "startTime" => (Time.current.to_i - 86400) * 1000, "pageSize" => 1)
      true
    rescue => e
      Rails.logger.warn("[BingxClient] Ping failed: #{e.message}")
      false
    end

    def signed_get(path, params = {})
      timestamp = (Time.now.to_f * 1000).to_i
      params = params.merge("timestamp" => timestamp)
      query = params.sort.map { |k, v| "#{k}=#{v}" }.join("&")
      signature = OpenSSL::HMAC.hexdigest("SHA256", @api_secret, query)

      uri = URI("#{BASE_URL}#{path}")
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
    end

    private

    def stablequote_pair?(symbol)
      return false if symbol.blank?
      quote = symbol.to_s.split("-").last.to_s.upcase
      STABLEQUOTE_SYMBOLS.include?(quote)
    end

    def normalize_order_to_trade(order)
      raw = order.is_a?(Hash) ? order : order.to_h
      order_id = (raw["orderId"] || raw["order_id"])&.to_s
      return nil if order_id.blank?

      symbol = (raw["symbol"] || "").to_s
      side = (raw["side"] || raw["type"])&.to_s&.downcase
      executed_at_ms = raw["updateTime"] || raw["time"] || raw["createdAt"] || raw["update_time"]
      executed_at = executed_at_ms ? Time.at(executed_at_ms.to_i / 1000.0).utc : nil
      return nil if executed_at.blank?

      price = (raw["price"] || 0).to_d
      qty = (raw["executedQty"] || raw["executed_qty"] || raw["origQty"] || raw["quantity"] || 0).to_d
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
  end
end
