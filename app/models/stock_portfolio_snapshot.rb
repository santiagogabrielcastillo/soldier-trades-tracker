# frozen_string_literal: true

class StockPortfolioSnapshot < ApplicationRecord
  belongs_to :stock_portfolio

  SOURCES = %w[weekly monthly manual].freeze

  validates :total_value, presence: true, numericality: true
  validates :cash_flow, presence: true, numericality: true
  validates :recorded_at, presence: true
  validates :source, inclusion: { in: SOURCES }

  scope :ordered, -> { order(:recorded_at) }

  def deposit?
    cash_flow.to_d.positive?
  end

  def withdrawal?
    cash_flow.to_d.negative?
  end

  def snapshot_only?
    cash_flow.to_d.zero?
  end
end
