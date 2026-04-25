require "test_helper"

class Admin::Students::TradesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @admin.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: @admin.email, password: "password" }
    @student = users(:one)
    @trade = trades(:one)
  end

  test "index lists student trades" do
    get admin_student_trades_url(@student)
    assert_response :success
  end

  test "new renders form" do
    get new_admin_student_trade_url(@student)
    assert_response :success
  end

  test "create adds trade and rebuilds positions" do
    account = exchange_accounts(:one)
    assert_difference "Trade.unscoped.where(exchange_account: @student.exchange_accounts).count", 1 do
      post admin_student_trades_url(@student), params: {
        exchange_account_id: account.id,
        manual_trade: {
          symbol: "BTC-USDT", side: "buy", quantity: "0.1",
          price: "60000", executed_at: "2026-01-01T12:00",
          fee: "0", position_side: "LONG", leverage: "10",
          reduce_only: "0", realized_pnl: "0"
        }
      }
    end
    assert_redirected_to admin_student_path(@student)
  end

  test "edit renders form" do
    get edit_admin_student_trade_url(@student, @trade)
    assert_response :success
  end

  test "update modifies trade and rebuilds positions" do
    patch admin_student_trade_url(@student, @trade), params: {
      manual_trade: {
        symbol: "ETH-USDT", side: "buy", quantity: "1",
        price: "3000", executed_at: "2026-01-01T12:00",
        fee: "0", position_side: "LONG", leverage: "5",
        reduce_only: "0", realized_pnl: "0"
      }
    }
    assert_redirected_to admin_student_path(@student)
    assert_equal "ETH-USDT", @trade.reload.symbol
  end

  test "destroy soft-deletes trade" do
    assert_no_difference "Trade.unscoped.where(exchange_account: @student.exchange_accounts).count" do
      delete admin_student_trade_url(@student, @trade)
    end
    assert_redirected_to admin_student_path(@student)
    assert_not_nil @trade.reload.discarded_at
  end

  test "non-admin cannot access" do
    student2 = users(:two)
    student2.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: student2.email, password: "password" }
    get admin_student_trades_url(@student)
    assert_redirected_to root_path
  end
end
