# frozen_string_literal: true

module Exchanges
  # Centralizes trade financial math so sign conventions and formula are exchange-agnostic.
  # Sign convention: fee is stored as provided (typically negative = cost). net_amount: positive = inflow (sell),
  # negative = outflow (buy). All math uses BigDecimal; outputs rounded to 8 decimals to match trades columns.
  class FinancialCalculator
    SCALE = 8

    # @param price [Numeric, String] price per unit
    # @param quantity [Numeric, String] quantity
    # @param side [String] "buy", "sell", or "close"
    # @param fee_from_exchange [Numeric, String, nil] commission from exchange (typically negative); nil/blank => 0
    # @return [Hash] { fee:, net_amount: } both BigDecimal, rounded to SCALE
    def self.compute(price:, quantity:, side:, fee_from_exchange: nil)
      price = price.to_d
      quantity = quantity.to_d
      fee = (fee_from_exchange.blank? ? 0 : fee_from_exchange).to_d
      notional = (price * quantity).round(SCALE)
      net_amount = case side.to_s.downcase
      when "sell"
        (notional - fee).round(SCALE)
      when "buy", "close"
        (-notional - fee).round(SCALE)
      else
        (-notional - fee).round(SCALE)
      end
      { fee: fee.round(SCALE), net_amount: net_amount }
    end
  end
end
