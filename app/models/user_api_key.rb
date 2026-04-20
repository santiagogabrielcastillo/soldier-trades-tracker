# frozen_string_literal: true

class UserApiKey < ApplicationRecord
  PROVIDERS = %w[finnhub coingecko iol anthropic gemini].freeze

  belongs_to :user

  encrypts :key
  encrypts :secret

  validates :provider, inclusion: { in: PROVIDERS }
  validates :provider, uniqueness: { scope: :user_id }
  validates :key, presence: true

  def self.key_for(user, provider)
    user.user_api_keys.find_by(provider: provider.to_s)&.key
  end

  def self.credentials_for(user, provider)
    row = user.user_api_keys.find_by(provider: provider.to_s)
    row ? { key: row.key, secret: row.secret } : nil
  end
end
