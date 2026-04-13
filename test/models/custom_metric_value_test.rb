# frozen_string_literal: true

require "test_helper"

class CustomMetricValueTest < ActiveSupport::TestCase
  setup do
    @company = users(:one).companies.create!(ticker: "TEST", name: "Test Co")
    @report  = @company.earnings_reports.create!(period_type: "annual", fiscal_year: 2024)
    @number_defn     = @company.custom_metric_definitions.create!(name: "ARR", data_type: "number")
    @percentage_defn = @company.custom_metric_definitions.create!(name: "Margin", data_type: "percentage")
    @text_defn       = @company.custom_metric_definitions.create!(name: "Guidance", data_type: "text")
  end

  test "number type: decimal_value is stored, text_value is nil" do
    val = @report.custom_metric_values.build(
      custom_metric_definition: @number_defn,
      decimal_value: 42.5
    )
    assert val.valid?, val.errors.full_messages.inspect
  end

  test "percentage type: decimal_value is stored, text_value is nil" do
    val = @report.custom_metric_values.build(
      custom_metric_definition: @percentage_defn,
      decimal_value: 38.5
    )
    assert val.valid?, val.errors.full_messages.inspect
  end

  test "text type: text_value is stored, decimal_value is nil" do
    val = @report.custom_metric_values.build(
      custom_metric_definition: @text_defn,
      text_value: "Strong demand"
    )
    assert val.valid?, val.errors.full_messages.inspect
  end

  test "number type: text_value must be blank" do
    val = @report.custom_metric_values.build(
      custom_metric_definition: @number_defn,
      decimal_value: 10,
      text_value: "oops"
    )
    assert_not val.valid?
    assert_includes val.errors[:text_value], "must be blank for number metrics"
  end

  test "text type: decimal_value must be blank" do
    val = @report.custom_metric_values.build(
      custom_metric_definition: @text_defn,
      text_value: "hello",
      decimal_value: 99
    )
    assert_not val.valid?
    assert_includes val.errors[:decimal_value], "must be blank for text metrics"
  end

  test "unique per earnings_report and custom_metric_definition" do
    @report.custom_metric_values.create!(custom_metric_definition: @number_defn, decimal_value: 10)
    duplicate = @report.custom_metric_values.build(custom_metric_definition: @number_defn, decimal_value: 20)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:custom_metric_definition_id], "has already been taken"
  end

  test "formatted_value for number" do
    val = @report.custom_metric_values.build(custom_metric_definition: @number_defn, decimal_value: 1_234_567_890)
    assert_equal "1234567890.0", val.formatted_value
  end

  test "formatted_value for percentage" do
    val = @report.custom_metric_values.build(custom_metric_definition: @percentage_defn, decimal_value: 38.57)
    assert_equal "38.57%", val.formatted_value
  end

  test "formatted_value for text" do
    val = @report.custom_metric_values.build(custom_metric_definition: @text_defn, text_value: "Good quarter")
    assert_equal "Good quarter", val.formatted_value
  end
end
