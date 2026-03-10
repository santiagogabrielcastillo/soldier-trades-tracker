# frozen_string_literal: true

require "test_helper"

class Dashboards::SummaryServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    @account = exchange_accounts(:one)
  end

  test "portfolio summary includes total return pct when initial_balance > 0" do
    Trade.where(exchange_account: @account).delete_all
    portfolio = Portfolio.create!(user: @user, name: "Test", start_date: 1.week.ago, end_date: 1.day.from_now, initial_balance: 100, default: true)
    create_closed_position(profit: 10)
    result = Dashboards::SummaryService.call(@user)
    assert_equal 110, result[:summary_balance].to_f
    assert_equal 10.0, result[:summary_total_return_pct]
  end

  test "all time summary has nil total return pct" do
    @user.portfolios.update_all(default: false)
    create_closed_position(profit: 5)
    result = Dashboards::SummaryService.call(@user)
    assert_nil result[:summary_total_return_pct]
  end

  test "win rate and avg win/loss from closed positions" do
    Trade.where(exchange_account: @account).delete_all
    portfolio = Portfolio.create!(user: @user, name: "Test", start_date: 2.weeks.ago, end_date: 1.day.from_now, initial_balance: 0, default: true)
    create_closed_position(profit: 20)   # winner
    create_closed_position(profit: -5, position_id: "pos2")  # loser
    result = Dashboards::SummaryService.call(@user)
    assert_equal 2, result[:summary_closed_count]
    assert_equal 50.0, result[:summary_win_rate]
    assert_equal 20.0, result[:summary_avg_win]
    assert_equal(-5.0, result[:summary_avg_loss])
  end

  test "chart series from closed positions sorted by close_at" do
    Trade.where(exchange_account: @account).delete_all
    portfolio = Portfolio.create!(user: @user, name: "Test", start_date: 2.weeks.ago, end_date: 1.day.from_now, initial_balance: 50, default: true)
    create_closed_position(profit: 10)
    result = Dashboards::SummaryService.call(@user)
    assert result[:chart_balance_series].is_a?(Array)
    assert result[:chart_cumulative_pl_series].is_a?(Array)
    assert_equal 1, result[:chart_balance_series].size
    assert_equal "date", result[:chart_balance_series].first.keys.first.to_s
    assert_equal "value", result[:chart_balance_series].first.keys.second.to_s
  end

  test "summary includes unrealized_pl (zero when no open positions)" do
    Trade.where(exchange_account: @account).delete_all
    portfolio = Portfolio.create!(user: @user, name: "Test", start_date: 2.weeks.ago, end_date: 1.day.from_now, initial_balance: 0, default: true)
    create_closed_position(profit: 10)
    result = Dashboards::SummaryService.call(@user)
    assert result.key?(:summary_unrealized_pl)
    assert_equal 0, result[:summary_unrealized_pl].to_f, "No open positions => unrealized PnL is 0"
  end

  test "no closed positions yields empty chart series and nil win rate" do
    portfolio = Portfolio.create!(user: @user, name: "Test", start_date: 2.weeks.ago, end_date: 1.day.from_now, initial_balance: 100, default: true)
    # Only open trade, no close
    Trade.create!(
      exchange_account_id: @account.id,
      exchange_reference_id: "ref_open_only",
      symbol: "BTC-USDT",
      side: "BUY",
      fee: 0,
      net_amount: -100,
      executed_at: Time.current,
      raw_payload: { "side" => "BUY", "executedQty" => "1", "avgPrice" => "100", "positionID" => "pos_open", "reduceOnly" => false, "leverage" => "10X" },
      position_id: "pos_open"
    )
    result = Dashboards::SummaryService.call(@user)
    assert_equal 0, result[:summary_closed_count]
    assert_nil result[:summary_win_rate]
    assert_nil result[:summary_avg_win]
    assert_nil result[:summary_avg_loss]
    assert_equal [], result[:chart_balance_series]
    assert_equal [], result[:chart_cumulative_pl_series]
  end

  private

  def create_closed_position(profit:, position_id: "pos1")
    base = 1.week.ago
    Trade.create!(
      exchange_account_id: @account.id,
      exchange_reference_id: "ref_#{position_id}_open",
      symbol: "BTC-USDT",
      side: "BUY",
      fee: 0,
      net_amount: -100,
      executed_at: base,
      raw_payload: { "side" => "BUY", "executedQty" => "1", "avgPrice" => "100", "positionID" => position_id, "reduceOnly" => false, "leverage" => "10X" },
      position_id: position_id
    )
    Trade.create!(
      exchange_account_id: @account.id,
      exchange_reference_id: "ref_#{position_id}_close",
      symbol: "BTC-USDT",
      side: "SELL",
      fee: 0,
      net_amount: 100 + profit,
      executed_at: base + 1.hour,
      raw_payload: { "side" => "SELL", "executedQty" => "1", "avgPrice" => (100 + profit).to_s, "positionID" => position_id, "reduceOnly" => true, "profit" => profit.to_s },
      position_id: position_id
    )
  end
end
