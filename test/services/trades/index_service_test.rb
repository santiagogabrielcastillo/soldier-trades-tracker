# frozen_string_literal: true

require "test_helper"

class Trades::IndexServiceTest < ActiveSupport::TestCase
  # Minimal raw_payload so PositionSummary can build a position (needs qty and price for notional/open_qty).
  MINIMAL_RAW_PAYLOAD = { "side" => "BUY", "qty" => "1", "price" => "100" }.freeze

  setup do
    @user = users(:one)
    @account = exchange_accounts(:one)
  end

  test "history view returns exchange_accounts and positions" do
    result = Trades::IndexService.call(user: @user, view: "history")
    assert_equal "history", result[:view]
    assert result[:exchange_accounts].is_a?(Array)
    assert result[:positions].is_a?(Array)
  end

  test "history with exchange_account_id filters to that account's trades" do
    Trade.where(exchange_account: @account).delete_all
    Trade.create!(exchange_account: @account, exchange_reference_id: "h1", symbol: "BTC-USDT", side: "buy", fee: 0, net_amount: -100, executed_at: Time.current, raw_payload: MINIMAL_RAW_PAYLOAD.dup)
    other = ExchangeAccountKeyValidator.stub(:read_only?, true) do
      @user.exchange_accounts.create!(provider_type: "binance", api_key: "k", api_secret: "s")
    end
    Trade.create!(exchange_account: other, exchange_reference_id: "h2", symbol: "ETH-USDT", side: "buy", fee: 0, net_amount: -50, executed_at: Time.current, raw_payload: MINIMAL_RAW_PAYLOAD.dup)
    result = Trades::IndexService.call(user: @user, view: "history", exchange_account_id: @account.id)
    assert_equal 1, result[:positions].size
    assert_equal @account.id, result[:positions].first.exchange_account.id
  end

  test "exchange view with from_date filters trades" do
    Trade.where(exchange_account: @account).delete_all
    Trade.create!(exchange_account: @account, exchange_reference_id: "e1", symbol: "BTC-USDT", side: "buy", fee: 0, net_amount: -100, executed_at: 5.days.ago, raw_payload: MINIMAL_RAW_PAYLOAD.dup)
    result = Trades::IndexService.call(user: @user, view: "exchange", exchange_account_id: @account.id, from_date: 3.days.ago.to_date)
    assert_equal "exchange", result[:view]
    assert_equal 0, result[:positions].size
  end

  test "portfolio with exchange_account_id scopes to that account" do
    Trade.where(exchange_account: @account).delete_all
    Trade.create!(exchange_account: @account, exchange_reference_id: "p1", symbol: "BTC-USDT", side: "buy", fee: 0, net_amount: -100, executed_at: Time.current, raw_payload: MINIMAL_RAW_PAYLOAD.dup)
    portfolio = @user.portfolios.create!(name: "P", start_date: 1.month.ago.to_date, end_date: 1.day.from_now.to_date, exchange_account_id: @account.id)
    result = Trades::IndexService.call(user: @user, view: "portfolio", portfolio_id: portfolio.id)
    assert_equal 1, result[:positions].size
    assert_equal @account.id, result[:positions].first.exchange_account.id
  end
end
