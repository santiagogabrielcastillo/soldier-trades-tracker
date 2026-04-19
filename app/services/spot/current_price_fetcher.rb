# frozen_string_literal: true

module Spot
  # Fetches current spot prices for a list of tokens via CoinGecko.
  # Uses the user's CoinGecko API key if configured; works without one (free tier rate limits apply).
  # Results are cached for 2 minutes keyed on the sorted token list.
  class CurrentPriceFetcher
    def self.call(tokens:, user:)
      new(tokens: tokens, user: user).call
    end

    def initialize(tokens:, user:)
      @tokens  = tokens.to_a.map { |t| t.to_s.strip.upcase }.reject(&:blank?).uniq
      @api_key = UserApiKey.key_for(user, :coingecko)
    end

    def call
      return {} if @tokens.empty?

      cache_key = "spot_prices:#{@tokens.sort.join(',')}"
      Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
        Exchanges::Binance::SpotTickerFetcher.fetch_prices(tokens: @tokens, api_key: @api_key)
      end
    end
  end
end
