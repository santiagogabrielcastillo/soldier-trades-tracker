# frozen_string_literal: true

require "test_helper"

class PortfolioTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @account = exchange_accounts(:one)
    @portfolio = @user.portfolios.create!(name: "Test", start_date: 1.month.ago.to_date, end_date: 1.day.from_now.to_date)
  end

  test "trades_in_range with no exchange_account_id returns all user trades in date range" do
    Trade.where(exchange_account: @account).delete_all
    Trade.create!(exchange_account: @account, exchange_reference_id: "r1", symbol: "BTC-USDT", side: "buy", fee: 0, net_amount: -100, executed_at: Time.current, raw_payload: {})
    rel = @portfolio.trades_in_range
    assert_includes rel.map(&:id), Trade.find_by(exchange_reference_id: "r1").id
  end

  test "trades_in_range with exchange_account_id returns only that account's trades in range" do
    other_account = ExchangeAccountKeyValidator.stub(:read_only?, true) do
      @user.exchange_accounts.create!(provider_type: "binance", api_key: "k", api_secret: "s")
    end
    Trade.where(exchange_account: [@account, other_account]).delete_all
    Trade.create!(exchange_account: @account, exchange_reference_id: "acc1", symbol: "BTC-USDT", side: "buy", fee: 0, net_amount: -100, executed_at: Time.current, raw_payload: {})
    Trade.create!(exchange_account: other_account, exchange_reference_id: "acc2", symbol: "ETH-USDT", side: "buy", fee: 0, net_amount: -50, executed_at: Time.current, raw_payload: {})
    @portfolio.update!(exchange_account_id: @account.id)
    rel = @portfolio.trades_in_range
    assert_equal 1, rel.size
    assert_equal @account.id, rel.first.exchange_account_id
  end

  test "validation rejects exchange_account_id belonging to another user" do
    other_user_account = exchange_accounts(:two)
    @portfolio.exchange_account_id = other_user_account.id
    assert_not @portfolio.valid?
    assert_includes @portfolio.errors[:exchange_account_id], "must be one of your exchange accounts"
  end
end
