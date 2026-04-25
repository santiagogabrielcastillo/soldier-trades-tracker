require "test_helper"

class Admin::Students::SpotTransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @admin.update!(password: "password", password_confirmation: "password")
    post login_url, params: { email: @admin.email, password: "password" }
    @student = users(:one)
    @account = spot_accounts(:one)
    @tx      = spot_transactions(:one)
  end

  test "index lists spot transactions" do
    get admin_student_spot_transactions_url(@student)
    assert_response :success
  end

  test "new renders form" do
    get new_admin_student_spot_transaction_url(@student, spot_account_id: @account.id)
    assert_response :success
  end

  test "create adds transaction" do
    assert_difference "SpotTransaction.unscoped.where(spot_account: @student.spot_accounts).count", 1 do
      post admin_student_spot_transactions_url(@student), params: {
        spot_account_id: @account.id,
        spot_transaction: {
          token: "BTC", side: "buy", price_usd: "60000",
          amount: "0.1", total_value_usd: "6000",
          executed_at: "2026-01-01T12:00",
          row_signature: "admin_sig_test_#{SecureRandom.hex(4)}"
        }
      }
    end
    assert_redirected_to admin_student_path(@student)
  end

  test "update modifies transaction" do
    patch admin_student_spot_transaction_url(@student, @tx), params: {
      spot_transaction: {
        token: "ETH", side: "buy", price_usd: "3000",
        amount: "1", total_value_usd: "3000",
        executed_at: "2026-01-01T12:00",
        row_signature: @tx.row_signature
      }
    }
    assert_redirected_to admin_student_path(@student)
    assert_equal "ETH", @tx.reload.token
  end

  test "destroy soft-deletes transaction" do
    assert_no_difference "SpotTransaction.unscoped.where(spot_account: @student.spot_accounts).count" do
      delete admin_student_spot_transaction_url(@student, @tx)
    end
    assert_not_nil @tx.reload.discarded_at
  end
end
