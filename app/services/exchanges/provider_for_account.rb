# frozen_string_literal: true

module Exchanges
  # Returns a provider client for an ExchangeAccount. Used by the sync job, dispatcher,
  # and validator so no code branches on provider_type or references BingxClient directly.
  class ProviderForAccount
    REGISTRY = {
      "binance" => "Exchanges::BinanceClient",
      "bingx" => "Exchanges::BingxClient"
    }.freeze

    def initialize(account)
      @account = account
    end

    # Returns a client that responds to fetch_my_trades(since:), or nil if provider is unsupported
    # or credentials are blank.
    def client
      return nil if @account.api_key.blank? || @account.api_secret.blank?

      class_name = REGISTRY[@account.provider_type.to_s.downcase]
      return nil unless class_name

      klass = class_name.constantize
      klass.new(
        api_key: @account.api_key,
        api_secret: @account.api_secret,
        allowed_quote_currencies: @account.allowed_quote_currencies
      )
    rescue ActiveRecord::Encryption::Errors::Decryption
      nil
    end

    # Lightweight check: registry + credentials only; does not instantiate the client.
    # Use #client when you need the actual client.
    def supported?
      return false unless REGISTRY.key?(@account.provider_type.to_s.downcase)
      @account.api_key.present? && @account.api_secret.present?
    rescue ActiveRecord::Encryption::Errors::Decryption
      false
    end

    # Validates credentials via provider ping. Returns true if valid/read-only, false otherwise.
    # Call with provider_type + credentials (e.g. before save).
    def self.ping?(provider_type:, api_key:, api_secret:)
      return true if api_key.blank? || api_secret.blank?

      class_name = REGISTRY[provider_type.to_s.downcase]
      return true unless class_name

      klass = class_name.constantize
      return true unless klass.respond_to?(:ping)

      klass.ping(api_key: api_key, api_secret: api_secret)
    end
  end
end
