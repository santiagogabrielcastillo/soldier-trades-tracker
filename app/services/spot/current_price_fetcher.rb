# frozen_string_literal: true

module Spot
  # Fetches current spot prices for a list of tokens via the public Binance ticker API.
  # No exchange account required — the endpoint is unauthenticated.
  # Results are cached for 2 minutes keyed on the sorted token list.
  # Returns Hash token => BigDecimal price; empty on fetch failure.
  class CurrentPriceFetcher
    def self.call(tokens:)
      new(tokens: tokens).call
    end

    def initialize(tokens:)
      @tokens = tokens.to_a.map { |t| t.to_s.strip.upcase }.reject(&:blank?).uniq
    end

    def call
      return {} if @tokens.empty?

      cache_key = "spot_prices:#{@tokens.sort.join(',')}"
      Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
        Exchanges::Binance::SpotTickerFetcher.fetch_prices(tokens: @tokens)
      end
    end
  end
end
