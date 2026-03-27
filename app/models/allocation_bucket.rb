# frozen_string_literal: true

class AllocationBucket < ApplicationRecord
  COLORS = %w[#6366f1 #8b5cf6 #06b6d4 #10b981 #f59e0b #ef4444 #ec4899 #84cc16].freeze

  belongs_to :user
  has_many :allocation_manual_entries, dependent: :destroy
  has_many :stock_portfolios, foreign_key: :allocation_bucket_id, dependent: :nullify, inverse_of: :allocation_bucket
  has_many :spot_accounts, foreign_key: :allocation_bucket_id, dependent: :nullify, inverse_of: :allocation_bucket

  validates :name, presence: true
  validates :color, presence: true
  validates :target_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  scope :ordered, -> { order(:position, :id) }

  before_create :assign_color

  private

  def assign_color
    return if color.present?
    used = user.allocation_buckets.pluck(:color)
    self.color = (COLORS - used).first || COLORS.sample
  end
end
