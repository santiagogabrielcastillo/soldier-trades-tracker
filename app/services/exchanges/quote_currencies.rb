# frozen_string_literal: true

module Exchanges
  # Stablecoin quote currencies recognized across all exchange clients and the trade normalizer.
  # When adding a new currency here, also verify Binance::TradeNormalizer can format its symbols
  # correctly (it uses SUPPORTED to insert the hyphen separator in normalize_symbol).
  module QuoteCurrencies
    SUPPORTED = %w[USDT USDC BUSD].freeze
    DEFAULT = %w[USDT USDC].freeze
  end
end
