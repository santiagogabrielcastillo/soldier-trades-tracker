# frozen_string_literal: true

require "test_helper"

class ManualTradesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    @other_user = users(:two)
    @other_user.update!(password: "password", password_confirmation: "password")
    @account = exchange_accounts(:one)
  end

  # --- Authentication ---

  test "all actions require login" do
    get new_exchange_account_manual_trade_path(@account)
    assert_redirected_to login_path

    post exchange_account_manual_trades_path(@account), params: { manual_trade: valid_params }
    assert_redirected_to login_path

    trade = create_manual_trade
    get edit_exchange_account_manual_trade_path(@account, trade)
    assert_redirected_to login_path

    patch exchange_account_manual_trade_path(@account, trade), params: { manual_trade: valid_params }
    assert_redirected_to login_path

    delete exchange_account_manual_trade_path(@account, trade)
    assert_redirected_to login_path
  end

  # --- GET new ---

  test "GET new returns 200" do
    sign_in_as(@user)
    get new_exchange_account_manual_trade_path(@account)
    assert_response :success
  end

  # --- POST create ---

  test "POST create with valid params saves trade and rebuilds positions" do
    sign_in_as(@user)
    Positions::RebuildForAccountService.stub(:call, true) do
      assert_difference("Trade.count", 1) do
        post exchange_account_manual_trades_path(@account), params: { manual_trade: valid_params }
      end
    end
    assert_redirected_to trades_path
    assert_match(/Trade added/, flash[:notice])
  end

  test "POST create with invalid params re-renders new with 422" do
    sign_in_as(@user)
    post exchange_account_manual_trades_path(@account), params: {
      manual_trade: valid_params.merge(symbol: "")
    }
    assert_response :unprocessable_entity
  end

  test "POST create scopes to current user's accounts (404 on another user's account)" do
    sign_in_as(@user)
    other_account = exchange_accounts(:two)
    post exchange_account_manual_trades_path(other_account), params: { manual_trade: valid_params }
    assert_response :not_found
  end

  # --- GET edit ---

  test "GET edit scopes to current user's accounts (404 on another user's account)" do
    sign_in_as(@user)
    other_account = exchange_accounts(:two)
    ts_ms = (Time.current.to_f * 1000).to_i
    other_trade = other_account.trades.create!(
      exchange_reference_id: "manual_#{ts_ms}_other001",
      symbol: "BTC-USDT",
      side: "buy",
      net_amount: -25000,
      executed_at: 1.day.ago,
      raw_payload: { "side" => "BUY", "executedQty" => "0.5", "avgPrice" => "50000.0",
                     "positionSide" => "LONG", "reduceOnly" => false, "profit" => "0" }
    )
    get edit_exchange_account_manual_trade_path(other_account, other_trade)
    assert_response :not_found
  end

  test "PATCH update scopes to current user's accounts (404 on another user's account)" do
    sign_in_as(@user)
    other_account = exchange_accounts(:two)
    ts_ms = (Time.current.to_f * 1000).to_i
    other_trade = other_account.trades.create!(
      exchange_reference_id: "manual_#{ts_ms}_other002",
      symbol: "BTC-USDT",
      side: "buy",
      net_amount: -25000,
      executed_at: 1.day.ago,
      raw_payload: { "side" => "BUY", "executedQty" => "0.5", "avgPrice" => "50000.0",
                     "positionSide" => "LONG", "reduceOnly" => false, "profit" => "0" }
    )
    patch exchange_account_manual_trade_path(other_account, other_trade), params: { manual_trade: valid_params }
    assert_response :not_found
  end

  test "DELETE destroy scopes to current user's accounts (404 on another user's account)" do
    sign_in_as(@user)
    other_account = exchange_accounts(:two)
    ts_ms = (Time.current.to_f * 1000).to_i
    other_trade = other_account.trades.create!(
      exchange_reference_id: "manual_#{ts_ms}_other003",
      symbol: "BTC-USDT",
      side: "buy",
      net_amount: -25000,
      executed_at: 1.day.ago,
      raw_payload: { "side" => "BUY", "executedQty" => "0.5", "avgPrice" => "50000.0",
                     "positionSide" => "LONG", "reduceOnly" => false, "profit" => "0" }
    )
    delete exchange_account_manual_trade_path(other_account, other_trade)
    assert_response :not_found
  end

  # --- DELETE destroy ---

  test "DELETE destroy deletes trade and rebuilds positions" do
    sign_in_as(@user)
    trade = create_manual_trade
    Positions::RebuildForAccountService.stub(:call, true) do
      assert_difference("Trade.count", -1) do
        delete exchange_account_manual_trade_path(@account, trade)
      end
    end
    assert_redirected_to trades_path
    assert_match(/Trade deleted/, flash[:notice])
  end

  test "DELETE destroy on non-manual trade redirects with alert" do
    sign_in_as(@user)
    non_manual = @account.trades.create!(
      exchange_reference_id: "ext_ref_123",
      symbol: "BTC-USDT",
      side: "buy",
      net_amount: 100,
      executed_at: 1.day.ago
    )
    delete exchange_account_manual_trade_path(@account, non_manual)
    assert_redirected_to trades_path
    assert_match(/Only manually-entered trades/, flash[:alert])
    assert Trade.exists?(non_manual.id)
  end

  # --- PATCH update ---

  test "PATCH update edits trade and rebuilds positions" do
    sign_in_as(@user)
    trade = create_manual_trade
    Positions::RebuildForAccountService.stub(:call, true) do
      patch exchange_account_manual_trade_path(@account, trade), params: {
        manual_trade: valid_params.merge(price: "99999.0")
      }
    end
    assert_redirected_to trades_path
    assert_match(/Trade updated/, flash[:notice])
    assert_equal "99999.0", trade.reload.raw_payload["avgPrice"]
  end

  test "PATCH update on non-manual trade redirects with alert" do
    sign_in_as(@user)
    non_manual = @account.trades.create!(
      exchange_reference_id: "ext_ref_456",
      symbol: "BTC-USDT",
      side: "buy",
      net_amount: 100,
      executed_at: 1.day.ago
    )
    patch exchange_account_manual_trade_path(@account, non_manual), params: {
      manual_trade: valid_params
    }
    assert_redirected_to trades_path
    assert_match(/Only manually-entered trades/, flash[:alert])
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end

  def valid_params
    {
      symbol: "BTC-USDT",
      side: "buy",
      quantity: "0.5",
      price: "50000.0",
      executed_at: "2026-01-01 12:00:00",
      fee: "1.0",
      position_side: "LONG",
      leverage: "10",
      reduce_only: "false",
      realized_pnl: "0"
    }
  end

  def create_manual_trade
    ts_ms = (Time.current.to_f * 1000).to_i
    @account.trades.create!(
      exchange_reference_id: "manual_#{ts_ms}_abcd1234",
      symbol: "BTC-USDT",
      side: "buy",
      net_amount: -25000,
      executed_at: 1.day.ago,
      raw_payload: {
        "side" => "BUY",
        "executedQty" => "0.5",
        "avgPrice" => "50000.0",
        "positionSide" => "LONG",
        "reduceOnly" => false,
        "profit" => "0"
      }
    )
  end
end
