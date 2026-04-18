# frozen_string_literal: true

module Stocks
  # Fetches current prices for a list of stock tickers via Finnhub.
  # Requires the user to have a Finnhub API key configured in user_api_keys.
  # Returns Hash ticker => BigDecimal; returns {} when key is missing or tickers is empty.
  class CurrentPriceFetcher
    def self.call(tickers:, user:)
      new(tickers: tickers, user: user).call
    end

    def self.build_client(api_key)
      FinnhubClient.new(api_key: api_key)
    end

    def initialize(tickers:, user:)
      @tickers = tickers.to_a.map { |t| t.to_s.strip.upcase }.reject(&:blank?).uniq
      @api_key = UserApiKey.key_for(user, :finnhub)
    end

    def call
      return {} if @tickers.empty?
      return {} if @api_key.blank?

      client = self.class.build_client(@api_key)
      mutex  = Mutex.new
      prices = {}

      threads = @tickers.map do |ticker|
        Thread.new do
          price = Rails.cache.fetch("finnhub_price:#{ticker}", expires_in: 5.minutes, skip_nil: true) do
            client.quote(ticker)
          end
          mutex.synchronize { prices[ticker] = price } if price
        end
      end
      threads.each(&:join)

      prices
    end
  end
end
