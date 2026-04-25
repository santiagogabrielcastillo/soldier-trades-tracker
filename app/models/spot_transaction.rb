# frozen_string_literal: true

class SpotTransaction < ApplicationRecord
  include Auditable
  include Discardable

  belongs_to :spot_account

  validates :executed_at, presence: true
  validates :token, presence: true
  validates :side, presence: true, inclusion: { in: %w[buy sell deposit withdraw] }
  validates :price_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :total_value_usd, presence: true, numericality: true
  validates :row_signature, presence: true, uniqueness: { scope: :spot_account_id }

  scope :trades, -> { where(side: %w[buy sell]) }
  scope :ordered_by_executed_at, -> { order(executed_at: :asc) }
  scope :newest_first, -> { order(executed_at: :desc) }
end
