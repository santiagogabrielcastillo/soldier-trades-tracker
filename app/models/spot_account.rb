# frozen_string_literal: true

class SpotAccount < ApplicationRecord
  include HasSingleDefault

  belongs_to :user
  belongs_to :allocation_bucket, optional: true
  has_many :spot_transactions, dependent: :destroy

  validates :name, presence: true

  scope :default_first, -> { order(default: :desc) }

  def self.find_or_create_default_for(user)
    return nil unless user
    account = user.spot_accounts.find_by(default: true) || user.spot_accounts.first
    return account if account
    user.spot_accounts.create!(name: "Default", default: true)
  end

  def prices_as_decimals
    (cached_prices || {}).transform_values { |v| BigDecimal(v.to_s) }
  end

  def cache_prices!(prices_hash)
    update!(cached_prices: prices_hash.transform_values(&:to_s), prices_synced_at: Time.current)
  end

  def cash_balance
    deposit_sum  = spot_transactions.where(side: "deposit").sum(:amount)
    withdraw_sum = spot_transactions.where(side: "withdraw").sum(:amount)
    sell_sum     = spot_transactions.where(side: "sell").sum(:total_value_usd)
    buy_sum      = spot_transactions.where(side: "buy").sum(:total_value_usd)
    (deposit_sum.to_d - withdraw_sum.to_d + sell_sum.to_d - buy_sum.to_d)
  end

  private

end
