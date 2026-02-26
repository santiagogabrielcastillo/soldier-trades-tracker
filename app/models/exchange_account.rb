class ExchangeAccount < ApplicationRecord
  PROVIDER_TYPES = %w[binance bingx].freeze

  belongs_to :user
  has_many :trades, dependent: :destroy
  has_many :sync_runs, dependent: :destroy

  encrypts :api_key
  encrypts :api_secret

  validate :read_only_api_key

  validates :provider_type, inclusion: { in: PROVIDER_TYPES }
  validates :api_key, :api_secret, presence: true

  # Rate limit: max 2 syncs per calendar day (UTC)
  def sync_runs_today_count
    sync_runs.where("ran_at >= ?", Time.current.utc.beginning_of_day).count
  end

  def can_sync?
    sync_runs_today_count < 2
  end

  private

  def read_only_api_key
    return if api_key.blank? || api_secret.blank?

    return if ExchangeAccountKeyValidator.read_only?(provider_type, api_key, api_secret)

    errors.add(:base, "API key must be read-only. Keys with Trade or Withdraw permissions are not allowed.")
  end
end
