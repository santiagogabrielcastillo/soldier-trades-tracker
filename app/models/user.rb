class User < ApplicationRecord
  has_secure_password

  encrypts :gemini_api_key

  SYNC_INTERVALS = %w[hourly daily twice_daily].freeze

  before_validation { self.email = email.to_s.strip.downcase }
  before_update :prevent_last_admin_deactivation

  validates :email, presence: true, uniqueness: true
  validates :sync_interval, inclusion: { in: SYNC_INTERVALS }, allow_nil: true
  validates :active, inclusion: { in: [ true, false ] }

  scope :active, -> { where(active: true) }

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

  private

  def prevent_last_admin_deactivation
    return unless admin? && will_save_change_to_active?(to: false)

    remaining = User.where(admin: true, active: true).where.not(id: id).count
    if remaining.zero?
      errors.add(:active, "cannot deactivate the last active admin")
      throw :abort
    end
  end
end
