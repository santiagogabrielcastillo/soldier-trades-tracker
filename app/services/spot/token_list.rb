# frozen_string_literal: true

module Spot
  # Curated list of common spot symbols for the "New transaction" token combobox.
  # Merged with tokens already in the user's spot account (hybrid list).
  class TokenList
    LIST = %w[
      AAVE ALGO ATOM AVAX BCH BNB BTC COMP CRV DOGE DOT ETH FIL LINK LTC MANA MATIC MKR SAND SNX SOL THETA UNI USDC USDT VET XLM XMR XRP YFI
    ].freeze
  end
end
