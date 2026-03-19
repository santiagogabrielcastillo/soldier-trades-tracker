# frozen_string_literal: true

module Stocks
  # Fetches current CEDEAR prices in ARS from the configured Argentine market provider.
  # Mirrors the Stocks::CurrentPriceFetcher interface: returns Hash<ticker, BigDecimal>.
  # Missing tickers (price unavailable) are omitted from the result.
  #
  # Provider is TBD (IOL or BYMA). Once decided, implement the client and swap it in
  # argentine_client below. Until then, returns {} gracefully.
  class ArgentineCurrentPriceFetcher
    def self.call(tickers:)
      new(tickers: tickers).call
    end

    def initialize(tickers:)
      @tickers = tickers.to_a.map { |t| t.to_s.strip.upcase }.reject(&:blank?).uniq
    end

    def call
      return {} if @tickers.empty?

      client = self.class.argentine_client
      @tickers.each_with_object({}) do |ticker, prices|
        price = client.quote(ticker)
        prices[ticker] = price if price
      end
    rescue NotImplementedError
      {}
    end

    def self.argentine_client
      # Swap this line when the Argentine market provider is decided:
      #   Stocks::IolClient.new   or   Stocks::BymaClient.new
      raise NotImplementedError, "Argentine market client not yet configured. Implement Stocks::IolClient or Stocks::BymaClient and set it here."
    end
  end
end
