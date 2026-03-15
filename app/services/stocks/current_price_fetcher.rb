# frozen_string_literal: true

module Stocks
  # Fetches current prices for a list of stock tickers via Finnhub.
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
      client = FinnhubClient.new
      @tickers.each_with_object({}) do |ticker, prices|
        price = client.quote(ticker)
        prices[ticker] = price if price
      end
    end
  end
end
