# frozen_string_literal: true

require "test_helper"

module Stocks
  class CashBalanceServiceTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @portfolio = @user.stock_portfolios.create!(name: "Test", market: "argentina", default: false)
    end

    test "returns zero with no trades and no cash flows" do
      assert_equal BigDecimal("0"), CashBalanceService.call(stock_portfolio: @portfolio)
    end

    test "sell proceeds increase cash" do
      add_trade(side: "sell", total_value: "1000")
      assert_equal BigDecimal("1000"), CashBalanceService.call(stock_portfolio: @portfolio)
    end

    test "buy costs decrease cash" do
      add_trade(side: "buy", total_value: "500")
      assert_equal BigDecimal("-500"), CashBalanceService.call(stock_portfolio: @portfolio)
    end

    test "sell minus buy gives remaining cash" do
      add_trade(side: "sell", total_value: "25")   # sell 5 × $5
      add_trade(side: "buy",  total_value: "20")   # buy 2 × $10
      assert_equal BigDecimal("5"), CashBalanceService.call(stock_portfolio: @portfolio)
    end

    test "deposit snapshot adds to cash" do
      add_snapshot(cash_flow: "10000")
      assert_equal BigDecimal("10000"), CashBalanceService.call(stock_portfolio: @portfolio)
    end

    test "withdrawal snapshot subtracts from cash" do
      add_snapshot(cash_flow: "10000")
      add_snapshot(cash_flow: "-3000")
      assert_equal BigDecimal("7000"), CashBalanceService.call(stock_portfolio: @portfolio)
    end

    test "combined: deposit + sells - buys" do
      add_snapshot(cash_flow: "50000")  # deposit
      add_trade(side: "buy",  total_value: "30000")
      add_trade(side: "sell", total_value: "5000")
      # 50000 - 30000 + 5000 = 25000
      assert_equal BigDecimal("25000"), CashBalanceService.call(stock_portfolio: @portfolio)
    end

    test "pure snapshot (cash_flow=0) does not affect balance" do
      add_snapshot(cash_flow: "0")
      assert_equal BigDecimal("0"), CashBalanceService.call(stock_portfolio: @portfolio)
    end

    private

    def add_trade(side:, total_value:)
      @portfolio.stock_trades.create!(
        ticker: "TEST",
        side: side,
        price_usd: BigDecimal("100"),
        shares: BigDecimal(total_value) / 100,
        total_value_usd: BigDecimal(total_value),
        executed_at: Time.current,
        row_signature: SecureRandom.hex(16)
      )
    end

    def add_snapshot(cash_flow:)
      @portfolio.stock_portfolio_snapshots.create!(
        total_value: BigDecimal("0"),
        cash_flow: BigDecimal(cash_flow),
        recorded_at: Time.current,
        source: "manual"
      )
    end
  end
end
