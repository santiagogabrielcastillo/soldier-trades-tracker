# frozen_string_literal: true

module Stocks
  # Fetches current prices for a list of stock tickers via Finnhub.
  # Fetches all tickers in parallel threads; caches each price for 5 minutes.
  # Returns Hash ticker => BigDecimal price; missing tickers are omitted.
  class CurrentPriceFetcher
    def self.call(tickers:)
      new(tickers: tickers).call
    end

    def initialize(tickers:)
      @tickers = tickers.to_a.uniq.map { |t| t.to_s.strip.upcase }.reject(&:blank?)
    end

    def call
      return {} if @tickers.empty?

      client = self.class.finnhub_client
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

    def self.finnhub_client
      FinnhubClient.new
    end
  end
end
