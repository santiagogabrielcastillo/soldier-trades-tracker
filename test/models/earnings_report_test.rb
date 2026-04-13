# frozen_string_literal: true

require "test_helper"

class EarningsReportTest < ActiveSupport::TestCase
  setup do
    @company = users(:one).companies.create!(ticker: "TEST", name: "Test Co")
  end

  test "valid quarterly report" do
    report = @company.earnings_reports.build(period_type: "quarterly", fiscal_year: 2024, fiscal_quarter: 4)
    assert report.valid?, report.errors.full_messages.inspect
  end

  test "valid annual report" do
    report = @company.earnings_reports.build(period_type: "annual", fiscal_year: 2024)
    assert report.valid?, report.errors.full_messages.inspect
  end

  test "quarterly report requires fiscal_quarter in 1..4" do
    report = @company.earnings_reports.build(period_type: "quarterly", fiscal_year: 2024, fiscal_quarter: nil)
    assert_not report.valid?
    assert_includes report.errors[:fiscal_quarter], "is required for quarterly reports"

    report.fiscal_quarter = 5
    assert_not report.valid?
    assert_includes report.errors[:fiscal_quarter], "must be between 1 and 4"
  end

  test "annual report must have nil fiscal_quarter" do
    report = @company.earnings_reports.build(period_type: "annual", fiscal_year: 2024, fiscal_quarter: 1)
    assert_not report.valid?
    assert_includes report.errors[:fiscal_quarter], "must be blank for annual reports"
  end

  test "period_type must be quarterly or annual" do
    report = @company.earnings_reports.build(period_type: "monthly", fiscal_year: 2024)
    assert_not report.valid?
    assert_includes report.errors[:period_type], "is not included in the list"
  end

  test "fiscal_year is required" do
    report = @company.earnings_reports.build(period_type: "annual", fiscal_year: nil)
    assert_not report.valid?
    assert_includes report.errors[:fiscal_year], "can't be blank"
  end

  test "period_label for quarterly" do
    report = @company.earnings_reports.build(period_type: "quarterly", fiscal_year: 2024, fiscal_quarter: 3)
    assert_equal "Q3 2024", report.period_label
  end

  test "period_label for annual" do
    report = @company.earnings_reports.build(period_type: "annual", fiscal_year: 2024)
    assert_equal "FY2024", report.period_label
  end

  test "destroying report cascades to custom_metric_values" do
    defn = @company.custom_metric_definitions.create!(name: "ARR", data_type: "number")
    report = @company.earnings_reports.create!(period_type: "annual", fiscal_year: 2023)
    report.custom_metric_values.create!(custom_metric_definition: defn, decimal_value: 100)
    assert_difference "CustomMetricValue.count", -1 do
      report.destroy
    end
  end
end
