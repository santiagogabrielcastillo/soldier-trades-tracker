class User < ApplicationRecord
  has_secure_password

  SYNC_INTERVALS = %w[hourly daily twice_daily].freeze

  validates :email, presence: true, uniqueness: true
  validates :sync_interval, inclusion: { in: SYNC_INTERVALS }, allow_nil: true

  has_many :exchange_accounts, dependent: :destroy
  has_many :trades, through: :exchange_accounts
  has_many :portfolios, dependent: :destroy
  has_many :user_preferences, dependent: :destroy

  def default_portfolio
    portfolios.find_by(default: true)
  end
end
