# frozen_string_literal: true

# Validates that an exchange API key is read-only (no Trade or Withdraw permissions).
# Uses Exchanges::ProviderForAccount.ping? so each supported provider can implement its own ping.
# Unsupported providers are accepted (true). A failed ping can mean invalid key, network error,
# or rate limit; the model uses a single user-facing message for any verification failure.
class ExchangeAccountKeyValidator
  def self.read_only?(provider_type, api_key, api_secret)
    Exchanges::ProviderForAccount.ping?(provider_type: provider_type, api_key: api_key, api_secret: api_secret)
  end
end
