# frozen_string_literal: true

class SpotAccount < ApplicationRecord
  belongs_to :user
  belongs_to :allocation_bucket, optional: true
  has_many :spot_transactions, dependent: :destroy

  validates :name, presence: true

  before_save :clear_other_defaults, if: :default?

  scope :default_first, -> { order(default: :desc) }

  def self.default_for(user)
    user.spot_accounts.find_by(default: true) || user.spot_accounts.first
  end

  def self.find_or_create_default_for(user)
    return nil unless user
    account = user.spot_accounts.find_by(default: true) || user.spot_accounts.first
    return account if account
    user.spot_accounts.create!(name: "Default", default: true)
  end

  def cash_balance
    deposit_sum = spot_transactions.where(side: "deposit").sum(:amount)
    withdraw_sum = spot_transactions.where(side: "withdraw").sum(:amount)
    (deposit_sum.to_d - withdraw_sum.to_d)
  end

  private

  def clear_other_defaults
    return unless default?
    SpotAccount.where(user_id: user_id).where.not(id: id).update_all(default: false)
  end
end
