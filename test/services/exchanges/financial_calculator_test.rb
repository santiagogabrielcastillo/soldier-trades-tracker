# frozen_string_literal: true

require "test_helper"

module Exchanges
  class FinancialCalculatorTest < ActiveSupport::TestCase
    test "sell: net_amount is notional minus fee (inflow)" do
      result = FinancialCalculator.compute(
        price: 100,
        quantity: 2,
        side: "sell",
        fee_from_exchange: -0.5
      )
      assert_equal BigDecimal("-0.5"), result[:fee]
      assert_equal BigDecimal("200.5"), result[:net_amount]
    end

    test "buy: net_amount is negative notional minus fee (outflow)" do
      result = FinancialCalculator.compute(
        price: 50,
        quantity: 4,
        side: "buy",
        fee_from_exchange: -0.1
      )
      assert_equal BigDecimal("-0.1"), result[:fee]
      # -notional - fee = -200 - (-0.1) = -199.9
      assert_equal BigDecimal("-199.9"), result[:net_amount]
    end

    test "close: same as buy (outflow)" do
      result = FinancialCalculator.compute(
        price: 10,
        quantity: 10,
        side: "close",
        fee_from_exchange: 0
      )
      assert_equal BigDecimal("0"), result[:fee]
      assert_equal BigDecimal("-100"), result[:net_amount]
    end

    test "nil fee_from_exchange treated as zero" do
      result = FinancialCalculator.compute(price: 1, quantity: 1, side: "sell", fee_from_exchange: nil)
      assert_equal BigDecimal("0"), result[:fee]
      assert_equal BigDecimal("1"), result[:net_amount]
    end

    test "string inputs coerced to BigDecimal" do
      result = FinancialCalculator.compute(
        price: "99.99",
        quantity: "3.5",
        side: "sell",
        fee_from_exchange: "-0.25"
      )
      notional = BigDecimal("99.99") * BigDecimal("3.5")
      assert_equal BigDecimal("-0.25"), result[:fee]
      assert_equal (notional - BigDecimal("-0.25")).round(8), result[:net_amount]
    end

    test "results rounded to 8 decimals" do
      result = FinancialCalculator.compute(
        price: "1.111111111",
        quantity: "3.333333333",
        side: "sell",
        fee_from_exchange: nil
      )
      assert_equal 8, FinancialCalculator::SCALE
      assert result[:net_amount].is_a?(BigDecimal)
      assert result[:fee].is_a?(BigDecimal)
      assert_equal result[:net_amount], result[:net_amount].round(8)
      assert_equal result[:fee], result[:fee].round(8)
    end

    test "zero quantity: notional zero, net_amount is -fee" do
      result = FinancialCalculator.compute(
        price: 100,
        quantity: 0,
        side: "sell",
        fee_from_exchange: -0.1
      )
      assert_equal BigDecimal("-0.1"), result[:fee]
      assert_equal BigDecimal("0.1"), result[:net_amount]
    end
  end
end
