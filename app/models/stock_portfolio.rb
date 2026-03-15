# frozen_string_literal: true

class StockPortfolio < ApplicationRecord
  belongs_to :user
  has_many :stock_trades, dependent: :destroy

  validates :name, presence: true

  before_save :clear_other_defaults, if: :default?

  scope :default_first, -> { order(default: :desc) }

  def self.find_or_create_default_for(user)
    return nil unless user
    portfolio = user.stock_portfolios.find_by(default: true) || user.stock_portfolios.first
    return portfolio if portfolio
    user.stock_portfolios.create!(name: "Default", default: true)
  end

  private

  def clear_other_defaults
    StockPortfolio.where(user_id: user_id).where.not(id: id).update_all(default: false)
  end
end
