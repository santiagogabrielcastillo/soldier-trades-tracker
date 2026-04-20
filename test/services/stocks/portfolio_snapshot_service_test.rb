# frozen_string_literal: true

require "test_helper"
require "ostruct"

module Stocks
  class PortfolioSnapshotServiceTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @portfolio = @user.stock_portfolios.create!(name: "Snapshot Svc Test", market: "us", default: false)
    end

    test "creates snapshot with only CASH entry when no open positions" do
      Stocks::PositionStateService.stub(:call, []) do
        Stocks::CashBalanceService.stub(:call, BigDecimal("5000")) do
          snap = Stocks::PortfolioSnapshotService.call(stock_portfolio: @portfolio)
          assert_equal 1, snap.positions_breakdown.size
          cash_entry = snap.positions_breakdown.find { |p| p["ticker"] == "CASH" }
          assert_not_nil cash_entry
          assert_in_delta 100.0, cash_entry["pct_of_total"], 0.01
        end
      end
    end

    test "creates snapshot with positions_data including open positions" do
      pos = OpenStruct.new(ticker: "AAPL", shares: BigDecimal("10"), open?: true)

      Stocks::PositionStateService.stub(:call, [pos]) do
        Stocks::CurrentPriceFetcher.stub(:call, { "AAPL" => BigDecimal("150") }) do
          Stocks::CashBalanceService.stub(:call, BigDecimal("500")) do
            snap = Stocks::PortfolioSnapshotService.call(stock_portfolio: @portfolio)

            assert_equal BigDecimal("2000"), snap.total_value  # 10*150 + 500

            aapl = snap.positions_breakdown.find { |p| p["ticker"] == "AAPL" }
            cash = snap.positions_breakdown.find { |p| p["ticker"] == "CASH" }

            assert_not_nil aapl
            assert_not_nil cash
            assert_in_delta 75.0, aapl["pct_of_total"], 0.01   # 1500/2000*100
            assert_in_delta 25.0, cash["pct_of_total"], 0.01   # 500/2000*100
          end
        end
      end
    end

    test "omits CASH entry when cash balance is zero" do
      pos = OpenStruct.new(ticker: "MSFT", shares: BigDecimal("5"), open?: true)

      Stocks::PositionStateService.stub(:call, [pos]) do
        Stocks::CurrentPriceFetcher.stub(:call, { "MSFT" => BigDecimal("200") }) do
          Stocks::CashBalanceService.stub(:call, BigDecimal("0")) do
            snap = Stocks::PortfolioSnapshotService.call(stock_portfolio: @portfolio)
            tickers = snap.positions_breakdown.map { |p| p["ticker"] }
            assert_not_includes tickers, "CASH"
          end
        end
      end
    end
  end
end
