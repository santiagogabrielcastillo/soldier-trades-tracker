# frozen_string_literal: true

module Stocks
  # Fetches current CEDEAR prices in ARS from InvertirOnline (IOL).
  # Mirrors the Stocks::CurrentPriceFetcher interface: returns Hash<ticker, BigDecimal>.
  # Missing tickers (price unavailable) are omitted from the result.
  class ArgentineCurrentPriceFetcher
    def self.call(tickers:)
      new(tickers: tickers).call
    end

    def initialize(tickers:)
      @tickers = tickers.to_a.map { |t| t.to_s.strip.upcase }.reject(&:blank?).uniq
    end

    # Fetches all tickers in parallel threads and caches each price for 5 minutes.
    # Cold load: ~1 HTTP round-trip (all tickers concurrently).
    # Warm load: cache hit, no HTTP.
    def call
      return {} if @tickers.empty?

      client = self.class.argentine_client
      mutex  = Mutex.new
      prices = {}

      threads = @tickers.map do |ticker|
        Thread.new do
          price = Rails.cache.fetch("iol_price:#{ticker}", expires_in: 5.minutes, skip_nil: true) do
            client.quote(ticker)
          end
          mutex.synchronize { prices[ticker] = price } if price
        end
      end
      threads.each(&:join)

      prices
    end

    def self.argentine_client
      Stocks::IolClient.new
    end
  end
end
