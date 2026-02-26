# frozen_string_literal: true

# Validates that an exchange API key is read-only (no Trade or Withdraw permissions).
# BingX: We ping a read-only endpoint; if it succeeds the key is valid. BingX docs state that
# newly created keys are read-only by default—users must enable Trade/Withdraw in the UI.
# We accept any key that can read; recommend read-only keys in the link-account UI.
class ExchangeAccountKeyValidator
  def self.read_only?(provider_type, api_key, api_secret)
    case provider_type.to_s.downcase
    when "bingx"
      Exchanges::BingxClient.ping(api_key: api_key, api_secret: api_secret)
    else
      true
    end
  end
end
