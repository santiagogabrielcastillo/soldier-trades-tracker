# frozen_string_literal: true

require "digest"

module Exchanges
  module Bingx
    # Normalizes BingX API payloads to the shared trade hash shape (trade-style or income-style).
    # Trade-style hashes have price, quantity, fee_from_exchange; job applies FinancialCalculator.
    # Income-style hashes have fee, net_amount from the exchange.
    module TradeNormalizer
      class << self
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
          fee_from_exchange = (raw["commission"] || raw["fee"] || 0).to_d

          {
            exchange_reference_id: order_id,
            symbol: symbol,
            side: side,
            price: price,
            quantity: qty,
            fee_from_exchange: fee_from_exchange,
            executed_at: executed_at,
            raw_payload: raw,
            position_id: (raw["positionID"] || raw["position_id"])&.to_s.presence
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
          fee_from_exchange = (raw["commission"] || raw["fee"] || 0).to_d

          fill_id = (raw["tradeId"] || raw["fillId"]).to_s.presence
          ts_ms = (raw["time"] || raw["updateTime"] || raw["createdAt"] || raw["update_time"]).to_i
          exchange_reference_id = fill_id.presence || "#{order_id}_#{ts_ms}_#{index}"

          {
            exchange_reference_id: exchange_reference_id,
            symbol: symbol,
            side: side,
            price: price,
            quantity: qty,
            fee_from_exchange: fee_from_exchange,
            executed_at: executed_at,
            raw_payload: raw,
            position_id: (raw["positionID"] || raw["position_id"])&.to_s.presence
          }
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
            raw_payload: raw,
            position_id: (raw["positionID"] || raw["position_id"])&.to_s.presence
          }
        end

        private

        def executed_at_from(raw, *time_keys)
          ms = time_keys.lazy.map { |k| raw[k] }.find(&:present?)
          ms ? Time.at(ms.to_i / 1000.0).utc : nil
        end
      end
    end
  end
end
