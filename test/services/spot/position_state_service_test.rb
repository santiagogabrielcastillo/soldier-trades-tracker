# frozen_string_literal: true

require "test_helper"

module Spot
  class PositionStateServiceTest < ActiveSupport::TestCase
    setup do
      @spot_account = spot_accounts(:one)
      @spot_account.spot_transactions.destroy_all
    end

    test "returns empty when no transactions" do
      result = PositionStateService.call(spot_account: @spot_account)
      assert_equal [], result
    end

    test "single buy yields one open position" do
      @spot_account.spot_transactions.create!(
        executed_at: Time.utc(2026, 1, 14, 10, 0),
        token: "BTC",
        side: "buy",
        price_usd: 50000,
        amount: 0.01,
        total_value_usd: 500,
        row_signature: "sig1"
      )
      result = PositionStateService.call(spot_account: @spot_account)
      assert_equal 1, result.size
      pos = result.first
      assert pos.open?
      assert_equal "BTC", pos.token
      assert_equal BigDecimal("0.01"), pos.balance
      assert_equal BigDecimal("500"), pos.net_usd_invested
      assert_equal BigDecimal("50000"), pos.breakeven
      assert_equal BigDecimal("0"), pos.realized_pnl
    end

    test "buy then full sell closes position and realized PnL is correct" do
      @spot_account.spot_transactions.create!(
        executed_at: Time.utc(2026, 1, 14, 10, 0),
        token: "BTC",
        side: "buy",
        price_usd: 50000,
        amount: 0.01,
        total_value_usd: 500,
        row_signature: "sig1"
      )
      @spot_account.spot_transactions.create!(
        executed_at: Time.utc(2026, 1, 15, 10, 0),
        token: "BTC",
        side: "sell",
        price_usd: 51000,
        amount: 0.01,
        total_value_usd: 510,
        row_signature: "sig2"
      )
      result = PositionStateService.call(spot_account: @spot_account)
      assert_equal 1, result.size
      pos = result.first
      assert_not pos.open?
      assert_equal BigDecimal("0"), pos.balance
      assert_equal BigDecimal("10"), pos.realized_pnl
    end

    test "two buys then partial sell: FIFO and remaining balance" do
      @spot_account.spot_transactions.create!(
        executed_at: Time.utc(2026, 1, 14, 10, 0),
        token: "ETH",
        side: "buy",
        price_usd: 3000,
        amount: 1,
        total_value_usd: 3000,
        row_signature: "sig1"
      )
      @spot_account.spot_transactions.create!(
        executed_at: Time.utc(2026, 1, 14, 11, 0),
        token: "ETH",
        side: "buy",
        price_usd: 3100,
        amount: 1,
        total_value_usd: 3100,
        row_signature: "sig2"
      )
      @spot_account.spot_transactions.create!(
        executed_at: Time.utc(2026, 1, 15, 10, 0),
        token: "ETH",
        side: "sell",
        price_usd: 3200,
        amount: 1,
        total_value_usd: 3200,
        row_signature: "sig3"
      )
      result = PositionStateService.call(spot_account: @spot_account)
      assert_equal 1, result.size
      pos = result.first
      assert pos.open?
      assert_equal BigDecimal("1"), pos.balance
      assert_equal BigDecimal("2900"), pos.net_usd_invested
      assert_equal BigDecimal("2900"), pos.breakeven
      assert_equal BigDecimal("200"), pos.realized_pnl
    end

    test "balance zero then buy starts new epoch" do
      @spot_account.spot_transactions.create!(
        executed_at: Time.utc(2026, 1, 14, 10, 0),
        token: "WLD",
        side: "buy",
        price_usd: 1,
        amount: 100,
        total_value_usd: 100,
        row_signature: "sig1"
      )
      @spot_account.spot_transactions.create!(
        executed_at: Time.utc(2026, 1, 14, 11, 0),
        token: "WLD",
        side: "sell",
        price_usd: 2,
        amount: 100,
        total_value_usd: 200,
        row_signature: "sig2"
      )
      @spot_account.spot_transactions.create!(
        executed_at: Time.utc(2026, 1, 15, 10, 0),
        token: "WLD",
        side: "buy",
        price_usd: 1.5,
        amount: 50,
        total_value_usd: 75,
        row_signature: "sig3"
      )
      result = PositionStateService.call(spot_account: @spot_account)
      assert_equal 2, result.size
      closed = result.find { |p| !p.open? }
      open_pos = result.find { |p| p.open? }
      assert closed
      assert open_pos
      assert_equal BigDecimal("50"), open_pos.balance
      assert_equal BigDecimal("75"), open_pos.net_usd_invested
      assert_equal BigDecimal("1.5"), open_pos.breakeven
    end

    test "gross_avg_price is unaffected by sells while net breakeven worsens on loss" do
      # Buy 1000 tokens at $1.00 => gross avg $1.00, net breakeven $1.00
      @spot_account.spot_transactions.create!(
        executed_at: Time.utc(2026, 1, 14, 10, 0),
        token: "ONDO",
        side: "buy",
        price_usd: 1.0,
        amount: 1000,
        total_value_usd: 1000,
        row_signature: "sig1"
      )
      # Sell 500 at $0.70 (at a loss)
      @spot_account.spot_transactions.create!(
        executed_at: Time.utc(2026, 1, 15, 10, 0),
        token: "ONDO",
        side: "sell",
        price_usd: 0.70,
        amount: 500,
        total_value_usd: 350,
        row_signature: "sig2"
      )
      result = PositionStateService.call(spot_account: @spot_account)
      pos = result.find { |p| p.open? }
      assert pos
      assert_equal BigDecimal("500"), pos.balance
      # gross_avg_price is still the original buy price — sells don't affect it
      assert_equal BigDecimal("1.0").round(8), pos.gross_avg_price
      # net breakeven worsens: (1000 - 350) / 500 = 1.30
      assert_equal BigDecimal("1.3").round(8), pos.breakeven
    end

    test "ignores deposit and withdraw transactions for positions" do
      @spot_account.spot_transactions.create!(
        executed_at: Time.utc(2026, 1, 14, 10, 0),
        token: "BTC",
        side: "buy",
        price_usd: 50000,
        amount: 0.01,
        total_value_usd: 500,
        row_signature: "sig1"
      )
      @spot_account.spot_transactions.create!(
        executed_at: Time.utc(2026, 1, 14, 11, 0),
        token: "USDT",
        side: "deposit",
        price_usd: 1,
        amount: 1000,
        total_value_usd: 1000,
        row_signature: "cash|#{Time.utc(2026, 1, 14, 11, 0).to_i}|abc123"
      )
      result = PositionStateService.call(spot_account: @spot_account)
      assert_equal 1, result.size, "Only BTC buy/sell should affect positions"
      assert_equal "BTC", result.first.token
      assert_equal BigDecimal("0.01"), result.first.balance
    end
  end
end
