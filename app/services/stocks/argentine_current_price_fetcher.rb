# frozen_string_literal: true

module Stocks
  # Fetches current CEDEAR prices in ARS from InvertirOnline (IOL).
  # Requires the user to have IOL credentials configured in user_api_keys
  # (key = username/email, secret = password).
  # Returns Hash<ticker, BigDecimal>; empty when credentials are missing.
  class ArgentineCurrentPriceFetcher
    def self.call(tickers:, user:)
      new(tickers: tickers, user: user).call
    end

    def self.build_client(username:, password:)
      Stocks::IolClient.new(username: username, password: password)
    end

    def initialize(tickers:, user:)
      @tickers = tickers.to_a.map { |t| t.to_s.strip.upcase }.reject(&:blank?).uniq
      @creds   = UserApiKey.credentials_for(user, :iol)
    end

    def call
      return {} if @tickers.empty?
      return {} if @creds.nil?

      client = self.class.build_client(username: @creds[:key], password: @creds[:secret])
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
  end
end
