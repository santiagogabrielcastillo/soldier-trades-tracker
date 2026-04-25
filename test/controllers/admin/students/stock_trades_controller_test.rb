require "test_helper"

class Admin::Students::StockTradesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @admin.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: @admin.email, password: "password" }
    @student   = users(:one)
    @portfolio = stock_portfolios(:one)
    @trade     = stock_trades(:one)
  end

  test "index lists stock trades" do
    get admin_student_stock_trades_url(@student)
    assert_response :success
  end

  test "create adds stock trade" do
    assert_difference "StockTrade.unscoped.where(stock_portfolio: @student.stock_portfolios).count", 1 do
      post admin_student_stock_trades_url(@student), params: {
        stock_portfolio_id: @portfolio.id,
        stock_trade: {
          ticker: "MSFT", side: "buy", price_usd: "400",
          shares: "5", total_value_usd: "2000",
          executed_at: "2026-01-01T12:00",
          row_signature: "admin_msft_#{SecureRandom.hex(4)}"
        }
      }
    end
    assert_redirected_to admin_student_path(@student)
  end

  test "update modifies stock trade" do
    patch admin_student_stock_trade_url(@student, @trade), params: {
      stock_trade: {
        ticker: "GOOGL", side: "buy", price_usd: "170",
        shares: "10", total_value_usd: "1700",
        executed_at: "2026-01-10T10:00",
        row_signature: @trade.row_signature
      }
    }
    assert_redirected_to admin_student_path(@student)
    assert_equal "GOOGL", @trade.reload.ticker
  end

  test "destroy soft-deletes stock trade" do
    delete admin_student_stock_trade_url(@student, @trade)
    assert_redirected_to admin_student_path(@student)
    assert_not_nil @trade.reload.discarded_at
  end
end
