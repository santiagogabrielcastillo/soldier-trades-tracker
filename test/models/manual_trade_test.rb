require "test_helper"

class ManualTradeTest < ActiveSupport::TestCase
  def valid_attrs
    {
      symbol:       "BTC-USDT",
      side:         "buy",
      quantity:     BigDecimal("0.5"),
      price:        BigDecimal("50000"),
      executed_at:  Time.zone.parse("2024-01-15 10:00:00"),
      fee:          BigDecimal("1.5"),
      position_side: "LONG",
      leverage:     10,
      reduce_only:  false,
      realized_pnl: BigDecimal("0")
    }
  end

  def build_manual_trade(attrs = {})
    ManualTrade.new(valid_attrs.merge(attrs))
  end

  # ── Validations ─────────────────────────────────────────────────────────────

  test "valid with all required fields" do
    mt = build_manual_trade
    assert mt.valid?, mt.errors.full_messages.inspect
  end

  test "invalid when symbol blank" do
    mt = build_manual_trade(symbol: "")
    assert mt.invalid?
    assert_includes mt.errors[:symbol], "can't be blank"
  end

  test "invalid when symbol not in BASE-QUOTE format" do
    mt = build_manual_trade(symbol: "BTCUSDT")
    assert mt.invalid?
    assert mt.errors[:symbol].any? { |msg| msg.include?("BASE-QUOTE") }
  end

  test "invalid when quantity zero or negative" do
    mt_zero = build_manual_trade(quantity: 0)
    assert mt_zero.invalid?
    assert mt_zero.errors[:quantity].any?

    mt_neg = build_manual_trade(quantity: -1)
    assert mt_neg.invalid?
    assert mt_neg.errors[:quantity].any?
  end

  test "invalid when price zero or negative" do
    mt_zero = build_manual_trade(price: 0)
    assert mt_zero.invalid?
    assert mt_zero.errors[:price].any?

    mt_neg = build_manual_trade(price: -100)
    assert mt_neg.invalid?
    assert mt_neg.errors[:price].any?
  end

  test "invalid when executed_at blank" do
    mt = build_manual_trade(executed_at: nil)
    assert mt.invalid?
    assert mt.errors[:executed_at].any?
  end

  # ── net_amount ───────────────────────────────────────────────────────────────

  test "net_amount is negative for buy" do
    mt = build_manual_trade(side: "buy", quantity: BigDecimal("1"), price: BigDecimal("100"))
    # net_amount = -(1 * 100) = -100
    assert_equal(-BigDecimal("100"), mt.send(:computed_net_amount))
  end

  test "net_amount is positive for sell" do
    mt = build_manual_trade(side: "sell", quantity: BigDecimal("1"), price: BigDecimal("100"))
    # net_amount = +(1 * 100) = 100
    assert_equal BigDecimal("100"), mt.send(:computed_net_amount)
  end

  # ── raw_payload ──────────────────────────────────────────────────────────────

  test "raw_payload contains all required BingX keys" do
    mt = build_manual_trade
    payload = mt.send(:build_raw_payload, "manual_pos_123")
    %w[side executedQty avgPrice positionSide reduceOnly positionID profit].each do |key|
      assert_includes payload.keys, key, "missing key: #{key}"
    end
  end

  test "raw_payload leverage formatted as '10X'" do
    mt = build_manual_trade(leverage: 10)
    payload = mt.send(:build_raw_payload, "manual_pos_123")
    assert_equal "10X", payload["leverage"]
  end

  test "raw_payload positionSide inferred from side when position_side blank" do
    mt_buy  = build_manual_trade(side: "buy",  position_side: nil)
    mt_sell = build_manual_trade(side: "sell", position_side: nil)
    assert_equal "LONG",  mt_buy.send(:build_raw_payload, "pos")["positionSide"]
    assert_equal "SHORT", mt_sell.send(:build_raw_payload, "pos")["positionSide"]
  end

  test "raw_payload reduceOnly is boolean" do
    mt_true  = build_manual_trade(reduce_only: true)
    mt_false = build_manual_trade(reduce_only: false)
    assert_equal true,  mt_true.send(:build_raw_payload,  "pos")["reduceOnly"]
    assert_equal false, mt_false.send(:build_raw_payload, "pos")["reduceOnly"]
  end

  # ── save / create ────────────────────────────────────────────────────────────

  test "save creates a Trade record with exchange_reference_id starting with manual_" do
    account = exchange_accounts(:one)
    mt = build_manual_trade
    mt.exchange_account = account

    assert mt.save, mt.errors.full_messages.inspect
    assert mt.trade_record.persisted?
    assert_match(/\Amanual_/, mt.trade_record.exchange_reference_id)
  end

  # ── from_trade round-trip ────────────────────────────────────────────────────

  test "from_trade round-trips symbol, side, quantity, price" do
    account = exchange_accounts(:one)
    mt = build_manual_trade(
      symbol:       "ETH-USDT",
      side:         "sell",
      quantity:     BigDecimal("2.5"),
      price:        BigDecimal("3000"),
      leverage:     5
    )
    mt.exchange_account = account
    assert mt.save, mt.errors.full_messages.inspect

    trade = mt.trade_record
    round_tripped = ManualTrade.from_trade(trade)

    assert_equal "ETH-USDT",         round_tripped.symbol
    assert_equal "sell",             round_tripped.side
    assert_equal BigDecimal("2.5"),  round_tripped.quantity
    assert_equal BigDecimal("3000"), round_tripped.price
  end
end
