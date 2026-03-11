# frozen_string_literal: true

module Spot
  # Fetches current spot prices for a list of tokens using one of the user's connected exchanges.
  # Picks first Binance account if available (spot ticker supported); otherwise first account (BingX spot not in MVP).
  # Returns Hash token => BigDecimal price; empty if no exchange or fetch fails.
  class CurrentPriceFetcher
    def self.call(user:, tokens:)
      new(user: user, tokens: tokens).call
    end

    def initialize(user:, tokens:)
      @user = user
      @tokens = tokens.to_a.uniq.map { |t| t.to_s.strip.upcase }.reject(&:blank?)
    end

    def call
      return {} if @tokens.empty?
      account = pick_exchange_account
      return {} unless account
      fetch_via(account)
    end

    private

    def pick_exchange_account
      binance = @user.exchange_accounts.find_by("LOWER(provider_type) = ?", "binance")
      return binance if binance
      @user.exchange_accounts.first
    end

    def fetch_via(account)
      case account.provider_type.to_s.downcase
      when "binance"
        Exchanges::Binance::SpotTickerFetcher.fetch_prices(tokens: @tokens)
      else
        Rails.logger.info("[Spot::CurrentPriceFetcher] No spot ticker for provider #{account.provider_type}; only Binance supported for spot prices.")
        {}
      end
    end
  end
end
