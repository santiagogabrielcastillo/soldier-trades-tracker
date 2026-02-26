class ExchangeAccount < ApplicationRecord
  PROVIDER_TYPES = %w[binance bingx].freeze

  belongs_to :user
  has_many :trades, dependent: :destroy

  encrypts :api_key
  encrypts :api_secret

  validate :read_only_api_key

  validates :provider_type, inclusion: { in: PROVIDER_TYPES }
  validates :api_key, :api_secret, presence: true

  private

  def read_only_api_key
    return if api_key.blank? || api_secret.blank?

    return if ExchangeAccountKeyValidator.read_only?(provider_type, api_key, api_secret)

    errors.add(:base, "API key must be read-only. Keys with Trade or Withdraw permissions are not allowed.")
  end
end
