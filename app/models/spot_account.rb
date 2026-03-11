# frozen_string_literal: true

class SpotAccount < ApplicationRecord
  belongs_to :user
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

  private

  def clear_other_defaults
    return unless default?
    SpotAccount.where(user_id: user_id).where.not(id: id).update_all(default: false)
  end
end
