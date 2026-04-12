# frozen_string_literal: true

class CustomMetricValue < ApplicationRecord
  belongs_to :earnings_report
  belongs_to :custom_metric_definition
end
