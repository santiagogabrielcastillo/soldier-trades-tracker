# frozen_string_literal: true

require "test_helper"

class CompanyTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "valid company saves" do
    company = @user.companies.build(ticker: "aapl", name: "Apple Inc.")
    assert company.valid?, company.errors.full_messages.inspect
  end

  test "ticker is upcased and stripped on validation" do
    company = @user.companies.build(ticker: "  aapl  ", name: "Apple")
    company.valid?
    assert_equal "AAPL", company.ticker
  end

  test "ticker is required" do
    company = @user.companies.build(ticker: nil, name: "Apple")
    assert_not company.valid?
    assert_includes company.errors[:ticker], "can't be blank"
  end

  test "name is required" do
    company = @user.companies.build(ticker: "AAPL", name: nil)
    assert_not company.valid?
    assert_includes company.errors[:name], "can't be blank"
  end

  test "ticker is unique per user" do
    @user.companies.create!(ticker: "AAPL", name: "Apple")
    duplicate = @user.companies.build(ticker: "aapl", name: "Apple Inc.")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:ticker], "has already been taken"
  end

  test "same ticker is allowed for different users" do
    @user.companies.create!(ticker: "AAPL", name: "Apple")
    other = users(:two).companies.build(ticker: "AAPL", name: "Apple")
    assert other.valid?
  end

  test "destroying company cascades to earnings_reports and custom_metric_definitions" do
    company = @user.companies.create!(ticker: "TEST", name: "Test Co")
    company.earnings_reports.create!(period_type: "annual", fiscal_year: 2024)
    company.custom_metric_definitions.create!(name: "ARR", data_type: "number")
    assert_difference "EarningsReport.count", -1 do
      assert_difference "CustomMetricDefinition.count", -1 do
        company.destroy
      end
    end
  end
end
