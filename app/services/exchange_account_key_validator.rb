# frozen_string_literal: true

# Validates that an exchange API key is read-only (no Trade or Withdraw permissions).
# Phase 2: Implement by calling exchange API (e.g. Binance/BingX account or permissions endpoint).
class ExchangeAccountKeyValidator
  def self.read_only?(_provider_type, _api_key, _api_secret)
    # TODO: Phase 2 - call exchange API to check key permissions; return false if Trade/Withdraw allowed.
    true
  end
end
