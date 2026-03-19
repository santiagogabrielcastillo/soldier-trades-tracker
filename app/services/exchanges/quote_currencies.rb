# frozen_string_literal: true

module Exchanges
  # Stablecoin quote currencies recognized across all exchange clients and the trade normalizer.
  #
  # IMPORTANT — adding a new currency has different effects per exchange:
  # - Binance: Binance::TradeNormalizer#normalize_symbol iterates SUPPORTED to insert the
  #   hyphen separator (e.g., BTCUSDC → BTC-USDC). Adding a currency here enables formatting.
  # - BingX: symbols arrive pre-hyphenated from the API. Bingx::TradeNormalizer does NOT
  #   use SUPPORTED for formatting. Verify BingX compatibility independently when adding here.
  module QuoteCurrencies
    SUPPORTED = %w[USDT USDC BUSD].freeze
    DEFAULT = %w[USDT USDC].freeze
  end
end
