# frozen_string_literal: true

class CustomMetricValue < ApplicationRecord
  belongs_to :earnings_report
  belongs_to :custom_metric_definition

  validates :custom_metric_definition_id, uniqueness: { scope: :earnings_report_id }
  validate :value_matches_data_type

  def formatted_value
    return nil unless custom_metric_definition

    case custom_metric_definition.data_type
    when "percentage"
      decimal_value ? "#{decimal_value.round(2)}%" : nil
    when "text"
      text_value.to_s
    when "money"
      decimal_value ? "$#{ActiveSupport::NumberHelper.number_to_delimited(decimal_value.round(2))}" : nil
    else
      decimal_value ? decimal_value.to_s : nil
    end
  end

  private

  def value_matches_data_type
    return unless custom_metric_definition

    case custom_metric_definition.data_type
    when "number", "percentage", "money"
      errors.add(:text_value, :must_be_blank_for_number) if text_value.present?
    when "text"
      errors.add(:decimal_value, :must_be_blank_for_text) if decimal_value.present?
    end
  end
end
