# frozen_string_literal: true

require "test_helper"

module Stocks
  class TwrCalculatorServiceTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @portfolio = @user.stock_portfolios.create!(name: "TWR Test", market: "argentina", default: false)
    end

    test "returns empty array with no snapshots" do
      assert_equal [], TwrCalculatorService.call(stock_portfolio: @portfolio)
    end

    test "returns empty array with only one snapshot" do
      add_snapshot(total_value: "100000", cash_flow: "0", recorded_at: 1.week.ago)
      assert_equal [], TwrCalculatorService.call(stock_portfolio: @portfolio)
    end

    test "calculates correct TWR for simple gain" do
      # Start: 100_000, no CF. End: 110_000. Return = 10%
      add_snapshot(total_value: "100000", cash_flow: "0", recorded_at: 2.weeks.ago)
      add_snapshot(total_value: "110000", cash_flow: "0", recorded_at: 1.week.ago)

      result = TwrCalculatorService.call(stock_portfolio: @portfolio)
      assert_equal 1, result.size
      assert_in_delta 10.0, result.first.twr_pct, 0.01
    end

    test "calculates correct TWR for simple loss" do
      add_snapshot(total_value: "100000", cash_flow: "0", recorded_at: 2.weeks.ago)
      add_snapshot(total_value: "90000",  cash_flow: "0", recorded_at: 1.week.ago)

      result = TwrCalculatorService.call(stock_portfolio: @portfolio)
      assert_in_delta(-10.0, result.first.twr_pct, 0.01)
    end

    test "neutralises cash flow in TWR calculation" do
      # Period 1: 100_000 → 110_000 (+10%). Then deposit 50_000.
      # Start of period 2: 110_000 + 50_000 = 160_000. End: 176_000 (+10%).
      # TWR = (1.10)(1.10) - 1 = 21%
      add_snapshot(total_value: "100000", cash_flow: "0",     recorded_at: 3.weeks.ago)
      add_snapshot(total_value: "110000", cash_flow: "50000", recorded_at: 2.weeks.ago)
      add_snapshot(total_value: "176000", cash_flow: "0",     recorded_at: 1.week.ago)

      result = TwrCalculatorService.call(stock_portfolio: @portfolio)
      assert_equal 2, result.size
      assert_in_delta 10.0, result[0].twr_pct, 0.01
      assert_in_delta 21.0, result[1].twr_pct, 0.01
    end

    test "TWR is unaffected by the size of a deposit" do
      # Same return (10%) both periods regardless of deposit amount
      add_snapshot(total_value: "100000",  cash_flow: "0",      recorded_at: 3.weeks.ago)
      add_snapshot(total_value: "110000",  cash_flow: "900000", recorded_at: 2.weeks.ago)
      add_snapshot(total_value: "1111000", cash_flow: "0",      recorded_at: 1.week.ago)

      result = TwrCalculatorService.call(stock_portfolio: @portfolio)
      assert_in_delta 21.0, result.last.twr_pct, 0.01
    end

    test "skips sub-period when start value is zero" do
      add_snapshot(total_value: "0",      cash_flow: "0", recorded_at: 2.weeks.ago)
      add_snapshot(total_value: "100000", cash_flow: "0", recorded_at: 1.week.ago)

      result = TwrCalculatorService.call(stock_portfolio: @portfolio)
      assert_equal [], result
    end

    test "returns date string for each twr point" do
      add_snapshot(total_value: "100000", cash_flow: "0", recorded_at: 2.weeks.ago)
      add_snapshot(total_value: "110000", cash_flow: "0", recorded_at: 1.week.ago)

      result = TwrCalculatorService.call(stock_portfolio: @portfolio)
      assert_match(/\A\d{4}-\d{2}-\d{2}\z/, result.first.date)
    end

    private

    def add_snapshot(total_value:, cash_flow:, recorded_at:)
      @portfolio.stock_portfolio_snapshots.create!(
        total_value: BigDecimal(total_value),
        cash_flow: BigDecimal(cash_flow),
        recorded_at: recorded_at,
        source: "manual"
      )
    end
  end
end
