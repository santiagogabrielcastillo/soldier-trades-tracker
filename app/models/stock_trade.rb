# frozen_string_literal: true

class StockTrade < ApplicationRecord
  include Auditable
  include Discardable

  belongs_to :stock_portfolio

  validates :executed_at, presence: true
  validates :ticker, presence: true
  validates :side, presence: true, inclusion: { in: %w[buy sell] }
  validates :price_usd, presence: true, numericality: { greater_than: 0 }
  validates :shares, presence: true, numericality: { greater_than: 0 }
  validates :total_value_usd, presence: true, numericality: true
  validates :row_signature, presence: true, uniqueness: { scope: :stock_portfolio_id }

  scope :ordered_by_executed_at, -> { order(executed_at: :asc) }
  scope :newest_first, -> { order(executed_at: :desc) }
end
