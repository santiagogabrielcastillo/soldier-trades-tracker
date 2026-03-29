# frozen_string_literal: true

module Spot
  # Fetches current spot prices for a list of tokens via the public Binance ticker API.
  # No exchange account required — the endpoint is unauthenticated.
  # Returns Hash token => BigDecimal price; empty on fetch failure.
  class CurrentPriceFetcher
    def self.call(tokens:, **)
      new(tokens: tokens).call
    end

    def initialize(tokens:, **)
      @tokens = tokens.to_a.uniq.map { |t| t.to_s.strip.upcase }.reject(&:blank?)
    end

    def call
      return {} if @tokens.empty?
      Exchanges::Binance::SpotTickerFetcher.fetch_prices(tokens: @tokens)
    end
  end
end
