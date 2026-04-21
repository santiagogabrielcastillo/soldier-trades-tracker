# frozen_string_literal: true

class CustomMetricDefinition < ApplicationRecord
  DATA_TYPES = %w[number percentage text money].freeze

  belongs_to :company

  has_many :custom_metric_values, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :data_type, presence: true, inclusion: { in: DATA_TYPES }

  scope :ordered, -> { order(:position, :name) }
end
