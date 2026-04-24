# frozen_string_literal: true

class StockPortfolio < ApplicationRecord
  MARKET_TYPES = %w[us argentina].freeze

  include HasSingleDefault

  belongs_to :user
  belongs_to :allocation_bucket, optional: true
  has_many :stock_trades, dependent: :destroy
  has_many :stock_portfolio_snapshots, dependent: :destroy

  validates :name, presence: true
  validates :market, inclusion: { in: MARKET_TYPES }

  validate :market_immutable_if_trades_exist, on: :update

  scope :default_first, -> { order(default: :desc) }

  def self.find_or_create_default_for(user)
    return nil unless user
    portfolio = user.stock_portfolios.find_by(default: true) || user.stock_portfolios.first
    return portfolio if portfolio
    user.stock_portfolios.create!(name: "Default", default: true)
  end

  def argentina?
    market == "argentina"
  end

  private

  def market_immutable_if_trades_exist
    if market_changed? && stock_trades.exists?
      errors.add(:market, :immutable_after_trades)
    end
  end
end
