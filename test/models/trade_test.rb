require "test_helper"

class TradeTest < ActiveSupport::TestCase
  test "manual? returns true when exchange_reference_id starts with manual_" do
    trade = Trade.new(exchange_reference_id: "manual_12345")
    assert trade.manual?
  end

  test "manual? returns false for exchange-synced trade" do
    trade = Trade.new(exchange_reference_id: "binance_abc123")
    assert_not trade.manual?
  end
end
