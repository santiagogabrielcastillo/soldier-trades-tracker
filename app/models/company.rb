# frozen_string_literal: true

class Company < ApplicationRecord
  belongs_to :user

  before_validation { self.ticker = ticker.to_s.strip.upcase }

  validates :ticker, presence: true, uniqueness: { scope: :user_id }
  validates :name, presence: true

  has_many :earnings_reports, dependent: :destroy
  has_many :custom_metric_definitions, dependent: :destroy

  scope :ordered, -> { order(:ticker) }
end
