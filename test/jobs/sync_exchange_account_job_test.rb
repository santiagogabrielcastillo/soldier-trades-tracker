# frozen_string_literal: true

require "test_helper"

class SyncExchangeAccountJobTest < ActiveJob::TestCase
  setup do
    # Create account via model so api_key/api_secret are encrypted in-process (avoids Decryption in job).
    ExchangeAccountKeyValidator.stub(:read_only?, true) do
      @account = ExchangeAccount.create!(
        user: users(:one),
        provider_type: "bingx",
        api_key: "test_key",
        api_secret: "test_secret",
        linked_at: 1.day.ago
      )
    end
  end

  test "perform uses FinancialCalculator for trade-style hashes and persists fee and net_amount" do
    trade_attrs = {
      exchange_reference_id: "ref-trade-1",
      symbol: "BTC-USDT",
      side: "sell",
      price: 100,
      quantity: 2,
      fee_from_exchange: -0.5,
      executed_at: 1.hour.ago,
      raw_payload: {}
    }
    client = build_fake_client([ trade_attrs ])
    Exchanges::BingxClient.stub(:new, client) do
      SyncExchangeAccountJob.perform_now(@account.id)
    end

    trade = Trade.find_by!(exchange_reference_id: "ref-trade-1")
    assert_equal BigDecimal("200.5"), trade.net_amount
    assert_equal BigDecimal("-0.5"), trade.fee
    assert_equal "sell", trade.side
    assert_equal "BTC-USDT", trade.symbol
  end

  test "perform keeps fee and net_amount from income-style hashes" do
    income_attrs = {
      exchange_reference_id: "ref-income-1",
      symbol: "BTC-USDT",
      side: "funding",
      fee: BigDecimal("-0.01"),
      net_amount: BigDecimal("1.5"),
      executed_at: 1.hour.ago,
      raw_payload: {}
    }
    client = build_fake_client([ income_attrs ])
    Exchanges::BingxClient.stub(:new, client) do
      SyncExchangeAccountJob.perform_now(@account.id)
    end

    trade = Trade.find_by!(exchange_reference_id: "ref-income-1")
    assert_equal BigDecimal("1.5"), trade.net_amount
    assert_equal BigDecimal("-0.01"), trade.fee
  end

  test "perform creates SyncRun and updates last_synced_at on success" do
    client = build_fake_client([])
    Exchanges::BingxClient.stub(:new, client) do
      SyncExchangeAccountJob.perform_now(@account.id)
    end
    @account.reload
    assert_equal 1, @account.sync_runs.count
    assert @account.last_synced_at.present?
  end

  test "perform deduplicates trades with same content but different exchange_reference_id (e.g. BingX V1 vs V2)" do
    executed_at = 1.hour.ago
    same_content = {
      symbol: "BTC-USDT",
      side: "sell",
      fee: BigDecimal("-0.5"),
      net_amount: BigDecimal("200.5"),
      executed_at: executed_at,
      raw_payload: {}
    }
    # Same logical trade, different ref IDs as from different BingX endpoints
    client = build_fake_client([
      same_content.merge(exchange_reference_id: "v1_order_123"),
      same_content.merge(exchange_reference_id: "v2_fill_456")
    ])
    Exchanges::BingxClient.stub(:new, client) do
      SyncExchangeAccountJob.perform_now(@account.id)
    end
    assert_equal 1, @account.trades.count, "should persist one trade when content matches"
    trade = @account.trades.first!
    assert_equal "BTC-USDT", trade.symbol
    assert_equal BigDecimal("200.5"), trade.net_amount
    assert [ "v1_order_123", "v2_fill_456" ].include?(trade.exchange_reference_id)
  end

  private

  def build_fake_client(trades)
    fake = Object.new
    fake.define_singleton_method(:fetch_my_trades) { |since:| trades }
    fake
  end
end
