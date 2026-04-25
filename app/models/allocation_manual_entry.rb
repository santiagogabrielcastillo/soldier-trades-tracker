# frozen_string_literal: true

class AllocationManualEntry < ApplicationRecord
  include Auditable
  include Discardable

  belongs_to :user
  belongs_to :allocation_bucket

  validates :label, presence: true
  validates :amount_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
