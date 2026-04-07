class User < ApplicationRecord
  has_secure_password

  encrypts :gemini_api_key

  SYNC_INTERVALS = %w[hourly daily twice_daily].freeze

  validates :email, presence: true, uniqueness: true
  validates :sync_interval, inclusion: { in: SYNC_INTERVALS }, allow_nil: true

  has_many :exchange_accounts, dependent: :destroy
  has_many :trades, through: :exchange_accounts
  has_many :portfolios, dependent: :destroy
  has_many :spot_accounts, dependent: :destroy
  has_many :stock_portfolios, dependent: :destroy
  has_many :user_preferences, dependent: :destroy
  has_many :cedear_instruments, dependent: :destroy
  has_many :watchlist_tickers, dependent: :destroy
  has_many :allocation_buckets, dependent: :destroy
  has_many :allocation_manual_entries, dependent: :destroy

  def default_portfolio
    portfolios.find_by(default: true)
  end

  def gemini_api_key_configured?
    gemini_api_key.present?
  end

  def gemini_api_key_masked
    return nil unless gemini_api_key.present? && gemini_api_key.length >= 8
    "#{gemini_api_key[0..3]}...#{gemini_api_key[-4..]}"
  end
end
