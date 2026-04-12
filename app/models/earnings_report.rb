# frozen_string_literal: true

class EarningsReport < ApplicationRecord
  PERIOD_TYPES = %w[quarterly annual].freeze

  belongs_to :company

  has_many :custom_metric_values, dependent: :destroy

  accepts_nested_attributes_for :custom_metric_values,
    reject_if: ->(attrs) { attrs[:decimal_value].blank? && attrs[:text_value].blank? }

  validates :period_type, inclusion: { in: PERIOD_TYPES }
  validates :fiscal_year, presence: true
  validates :fiscal_year,
    uniqueness: {
      scope: %i[company_id period_type],
      conditions: -> { where(fiscal_quarter: nil) },
      message: "already has an annual report for this year"
    },
    if: -> { period_type == "annual" }
  validates :fiscal_year,
    uniqueness: {
      scope: %i[company_id fiscal_quarter period_type],
      message: "already has a report for this quarter"
    },
    if: -> { period_type == "quarterly" }
  validate :fiscal_quarter_matches_period_type

  def period_label
    period_type == "annual" ? "FY#{fiscal_year}" : "Q#{fiscal_quarter} #{fiscal_year}"
  end

  private

  def fiscal_quarter_matches_period_type
    if period_type == "quarterly"
      if fiscal_quarter.nil?
        errors.add(:fiscal_quarter, "is required for quarterly reports")
      elsif !(1..4).cover?(fiscal_quarter)
        errors.add(:fiscal_quarter, "must be between 1 and 4")
      end
    elsif period_type == "annual"
      errors.add(:fiscal_quarter, "must be blank for annual reports") if fiscal_quarter.present?
    end
  end
end
