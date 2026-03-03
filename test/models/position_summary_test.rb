# frozen_string_literal: true

require "test_helper"

class PositionSummaryTest < ActiveSupport::TestCase
  setup do
    @account = exchange_accounts(:one)
  end

  test "#open? is true when position has no closing leg" do
    trades = [
      create_trade(account: @account, side: "BUY", qty: 1, avg_price: 100, position_id: "pos1", reduce_only: false)
    ]
    positions = PositionSummary.from_trades(trades)
    assert_equal 1, positions.size
    assert positions.first.open?, "Single opening trade with no close should be open"
  end

  test "#open? is false when position has a closing leg" do
    trades = [
      create_trade(account: @account, side: "BUY", qty: 1, avg_price: 100, position_id: "pos2", reduce_only: false),
      create_trade(account: @account, side: "SELL", qty: 1, avg_price: 105, position_id: "pos2", reduce_only: true, ref_suffix: "2")
    ]
    positions = PositionSummary.from_trades(trades)
    assert_equal 1, positions.size
    refute positions.first.open?, "Position with closing leg should not be open"
  end

  test "#entry_price from avgPrice in raw_payload" do
    trades = [
      create_trade(account: @account, side: "BUY", qty: 2, avg_price: 50.5, position_id: "pos3", reduce_only: false)
    ]
    positions = PositionSummary.from_trades(trades)
    assert_equal BigDecimal("50.5"), positions.first.entry_price
  end

  test "#entry_price from notional / open_quantity when avgPrice missing" do
    trades = [
      create_trade(account: @account, side: "BUY", qty: 4, avg_price: 25, position_id: "pos4", reduce_only: false)
    ]
    pos = PositionSummary.from_trades(trades).first
    # notional = 25 * 4 = 100, so entry = 100/4 = 25
    assert_equal BigDecimal("25"), pos.entry_price
  end

  test "#unrealized_pnl returns nil when not open" do
    trades = [
      create_trade(account: @account, side: "BUY", qty: 1, avg_price: 100, position_id: "p", reduce_only: false),
      create_trade(account: @account, side: "SELL", qty: 1, avg_price: 100, position_id: "p", reduce_only: true, ref_suffix: "c")
    ]
    pos = PositionSummary.from_trades(trades).first
    assert_nil pos.unrealized_pnl(105)
  end

  test "#unrealized_pnl returns nil when current_price is nil" do
    trades = [create_trade(account: @account, side: "BUY", qty: 1, avg_price: 100, position_id: "p", reduce_only: false)]
    pos = PositionSummary.from_trades(trades).first
    assert_nil pos.unrealized_pnl(nil)
  end

  test "#unrealized_pnl long: profit when current price above entry" do
    trades = [create_trade(account: @account, side: "BUY", qty: 2, avg_price: 100, position_id: "p", reduce_only: false)]
    pos = PositionSummary.from_trades(trades).first
    # (110 - 100) * 2 = 20
    assert_equal BigDecimal("20"), pos.unrealized_pnl(110)
  end

  test "#unrealized_pnl short: profit when current price below entry" do
    trades = [create_trade(account: @account, side: "SELL", qty: 3, avg_price: 50, position_id: "p", reduce_only: false)]
    pos = PositionSummary.from_trades(trades).first
    # (50 - 40) * 3 = 30
    assert_equal BigDecimal("30"), pos.unrealized_pnl(40)
  end

  test "#unrealized_roi_percent returns nil when margin_used blank" do
    trades = [create_trade(account: @account, side: "BUY", qty: 1, avg_price: 100, position_id: "p", reduce_only: false, leverage: nil)]
    pos = PositionSummary.from_trades(trades).first
    assert pos.open?
    assert_nil pos.unrealized_roi_percent(110)
  end

  test "#unrealized_roi_percent computes (unrealized_pnl / margin_used) * 100" do
    # margin = notional/leverage = 100*1/10 = 10, pnl = (110-100)*1 = 10, roi = 100%
    trades = [create_trade(account: @account, side: "BUY", qty: 1, avg_price: 100, position_id: "p", reduce_only: false, leverage: 10)]
    pos = PositionSummary.from_trades(trades).first
    roi = pos.unrealized_roi_percent(110)
    assert_not_nil roi
    assert_equal 100.0, roi
  end

  test "partial close yields closed leg row and remainder row (remaining open)" do
    # Open 3, close 1 -> closed leg (qty 1) + remainder row (qty 2 open). Margin 30 total; leg 10, remainder 20.
    trades = [
      create_trade(account: @account, side: "BUY", qty: 3, avg_price: 100, position_id: "pos_partial", reduce_only: false, leverage: 10),
      create_trade(account: @account, side: "SELL", qty: 1, avg_price: 105, position_id: "pos_partial", reduce_only: true, ref_suffix: "2")
    ]
    positions = PositionSummary.from_trades(trades)
    assert_equal 2, positions.size, "Should have one closed leg and one remainder row"
    closed_leg = positions.find { |p| !p.open? }
    remainder = positions.find { |p| p.open? }
    assert closed_leg, "One row should be closed leg"
    assert remainder, "One row should be remainder (open)"
    assert remainder.remaining_quantity.present?
    assert_equal BigDecimal("2"), remainder.remaining_quantity
    assert_equal 0, remainder.net_pl
    # Open margin = 300/10 = 30; remainder = 30 * (2/3) = 20
    assert_equal BigDecimal("20"), remainder.margin_used
    assert_equal 0, remainder.total_commission, "Remainder row shows no commission"
  end

  test "full close yields no remainder row" do
    trades = [
      create_trade(account: @account, side: "BUY", qty: 1, avg_price: 100, position_id: "pos_full", reduce_only: false),
      create_trade(account: @account, side: "SELL", qty: 1, avg_price: 105, position_id: "pos_full", reduce_only: true, ref_suffix: "2")
    ]
    positions = PositionSummary.from_trades(trades)
    assert_equal 1, positions.size
    refute positions.first.open?
  end

  private

  def create_trade(account:, side:, qty:, avg_price:, position_id:, reduce_only:, ref_suffix: "1", leverage: 10)
    ref_id = "ref_#{position_id}_#{ref_suffix}"
    payload = {
      "side" => side,
      "executedQty" => qty.to_s,
      "avgPrice" => avg_price.to_s,
      "positionID" => position_id,
      "reduceOnly" => reduce_only
    }
    payload["leverage"] = "#{leverage}X" if leverage
    Trade.create!(
      exchange_account_id: account.id,
      exchange_reference_id: ref_id,
      symbol: "BTC-USDT",
      side: side,
      fee: 0,
      net_amount: side == "BUY" ? -avg_price * qty : avg_price * qty,
      executed_at: Time.current,
      raw_payload: payload,
      position_id: position_id
    )
  end
end
