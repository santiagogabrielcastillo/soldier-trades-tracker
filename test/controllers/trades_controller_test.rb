# frozen_string_literal: true

require "test_helper"

class TradesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    @account = exchange_accounts(:one)
  end

  test "index redirects to login when not signed in" do
    get trades_path
    assert_redirected_to login_path
  end

  test "index returns 200 when signed in" do
    sign_in_as(@user)
    get trades_path(view: "history")
    assert_response :success
  end

  test "index includes default visible columns including Entry price when positions exist" do
    Trade.where(exchange_account: @account).delete_all
    create_open_trade
    sign_in_as(@user)
    get trades_path(view: "history")
    assert_response :success
    assert_select "th", text: "Entry price"
    assert_select "button", text: "Columns"
  end

  test "index shows Open and unrealized PnL when open position and price available" do
    Trade.where(exchange_account: @account).delete_all
    create_open_trade
    Exchanges::Bingx::TickerFetcher.stub(:fetch_prices, { "BTC-USDT" => BigDecimal("105") }) do
      sign_in_as(@user)
      get trades_path(view: "history")
      assert_response :success
      assert_select "td", text: "Open"
      # Unrealized PnL (105-100)*1 = 5
      assert_match(/5\.00/, response.body)
    end
  end

  test "index does not call ticker when no open positions" do
    Trade.where(exchange_account: @account).delete_all
    create_closed_trade
    call_count = 0
    Exchanges::Bingx::TickerFetcher.stub(:fetch_prices, ->(symbols:) { call_count += 1; {} }) do
      sign_in_as(@user)
      get trades_path(view: "history")
      assert_response :success
      assert_equal 0, call_count, "TickerFetcher should not be called when no open positions"
    end
  end

  test "index view=exchange with own exchange_account_id returns 200" do
    sign_in_as(@user)
    get trades_path(view: "exchange", exchange_account_id: @account.id)
    assert_response :success
  end

  test "index view=exchange with invalid exchange_account_id redirects to history with flash" do
    sign_in_as(@user)
    other_account = exchange_accounts(:two)
    get trades_path(view: "exchange", exchange_account_id: other_account.id)
    assert_redirected_to trades_path(view: "history")
    assert_match /wasn't found/i, flash[:alert].to_s
  end

  test "index shows closed leg and Open remainder row for partial close" do
    Trade.where(exchange_account: @account).delete_all
    create_partial_close_trades
    Exchanges::Bingx::TickerFetcher.stub(:fetch_prices, { "BTC-USDT" => BigDecimal("108") }) do
      sign_in_as(@user)
      get trades_path(view: "history")
      assert_response :success
      # Two rows for same position: one closed leg (PnL), one remainder (Open)
      assert_select "td", text: "Open"
      # Closed leg: sold 1 at 105, bought 1 at 100 -> profit 5
      assert_match(/5\.00/, response.body)
    end
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end

  def create_open_trade
    Trade.create!(
      exchange_account_id: @account.id,
      exchange_reference_id: "ref_open_#{SecureRandom.hex(4)}",
      symbol: "BTC-USDT",
      side: "BUY",
      fee: 0,
      net_amount: -100,
      executed_at: Time.current,
      raw_payload: {
        "side" => "BUY",
        "executedQty" => "1",
        "avgPrice" => "100",
        "positionID" => "pos_open",
        "reduceOnly" => false,
        "leverage" => "10X"
      },
      position_id: "pos_open"
    )
  end

  def create_partial_close_trades
    # Open 3, close 1 -> closed leg row + remainder (Open) row
    Trade.create!(
      exchange_account_id: @account.id,
      exchange_reference_id: "ref_partial_open",
      symbol: "BTC-USDT",
      side: "BUY",
      fee: 0,
      net_amount: -300,
      executed_at: 2.hours.ago,
      raw_payload: {
        "side" => "BUY",
        "executedQty" => "3",
        "avgPrice" => "100",
        "positionID" => "pos_partial",
        "reduceOnly" => false,
        "leverage" => "10X"
      },
      position_id: "pos_partial"
    )
    Trade.create!(
      exchange_account_id: @account.id,
      exchange_reference_id: "ref_partial_close",
      symbol: "BTC-USDT",
      side: "SELL",
      fee: 0,
      net_amount: 105,
      executed_at: 1.hour.ago,
      raw_payload: {
        "side" => "SELL",
        "executedQty" => "1",
        "avgPrice" => "105",
        "positionID" => "pos_partial",
        "reduceOnly" => true,
        "leverage" => "10X",
        "profit" => "5"
      },
      position_id: "pos_partial"
    )
  end

  def create_closed_trade
    Trade.create!(
      exchange_account_id: @account.id,
      exchange_reference_id: "ref_close_1",
      symbol: "ETH-USDT",
      side: "BUY",
      fee: 0,
      net_amount: -50,
      executed_at: 1.hour.ago,
      raw_payload: {
        "side" => "BUY",
        "executedQty" => "1",
        "avgPrice" => "50",
        "positionID" => "pos_closed",
        "reduceOnly" => false,
        "leverage" => "10X"
      },
      position_id: "pos_closed"
    )
    Trade.create!(
      exchange_account_id: @account.id,
      exchange_reference_id: "ref_close_2",
      symbol: "ETH-USDT",
      side: "SELL",
      fee: 0,
      net_amount: 55,
      executed_at: Time.current,
      raw_payload: {
        "side" => "SELL",
        "executedQty" => "1",
        "avgPrice" => "55",
        "positionID" => "pos_closed",
        "reduceOnly" => true,
        "leverage" => "10X"
      },
      position_id: "pos_closed"
    )
  end
end
