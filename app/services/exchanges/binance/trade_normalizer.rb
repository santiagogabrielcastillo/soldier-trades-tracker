# frozen_string_literal: true

module Exchanges
  module Binance
    # Normalizes Binance USDⓈ-M Futures userTrades payloads to the shared trade hash shape (trade-style).
    # Symbol format: BTCUSDT → BTC-USDT. Commission from API is negative (cost); we store absolute value for fee_from_exchange.
    module TradeNormalizer
      class << self
        # @param trade [Hash] one element from GET /fapi/v1/userTrades (id, symbol, side, price, qty, commission, realizedPnl, positionSide, time)
        # @return [Hash, nil] normalized trade hash or nil if required fields missing
        def user_trade_to_hash(trade)
          raw = trade.is_a?(Hash) ? trade : trade.to_h
          ref_id = (raw["id"] || raw["tradeId"])&.to_s
          return nil if ref_id.blank?

          executed_at = executed_at_from(raw["time"])
          return nil if executed_at.blank?

          symbol_raw = (raw["symbol"] || "").to_s
          symbol = normalize_symbol(symbol_raw)
          return nil if symbol.blank?

          side = (raw["side"] || "").to_s.downcase.presence || "buy"
          price = (raw["price"] || 0).to_d
          qty = (raw["qty"] || 0).to_d
          commission_raw = (raw["commission"] || 0).to_d
          fee_from_exchange = commission_raw.abs

          {
            exchange_reference_id: ref_id,
            symbol: symbol,
            side: side,
            price: price,
            quantity: qty,
            fee_from_exchange: fee_from_exchange,
            executed_at: executed_at,
            raw_payload: raw,
            position_id: (raw["positionSide"] || raw["position_side"])&.to_s.presence
          }
        end

        # Converts Binance symbol (e.g. BTCUSDT) to app format (e.g. BTC-USDT).
        def normalize_symbol(symbol)
          return nil if symbol.blank?
          s = symbol.to_s.strip.upcase
          return nil if s.empty?
          # Insert hyphen before common quote assets (USDT, USDC, BUSD, etc.)
          %w[USDT USDC BUSD].each do |quote|
            next unless s.end_with?(quote)
            base = s[0...(s.length - quote.length)]
            return "#{base}-#{quote}" if base.present?
          end
          s
        end

        private

        def executed_at_from(time_ms)
          return nil if time_ms.blank?
          Time.at(time_ms.to_i / 1000.0).utc
        end
      end
    end
  end
end
