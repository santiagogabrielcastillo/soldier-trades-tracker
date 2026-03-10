# frozen_string_literal: true

require "test_helper"

class UserPreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
  end

  test "update_trades_index_columns redirects to login when not signed in" do
    patch user_preferences_trades_index_columns_path, params: { column_ids: %w[symbol side] }
    assert_redirected_to login_path
  end

  test "update_trades_index_columns saves preference for history tab and redirects to trades" do
    sign_in_as(@user)
    patch user_preferences_trades_index_columns_path, params: { view: "history", column_ids: %w[closed symbol side] }
    assert_redirected_to trades_path(view: "history")
    assert_equal "Columns saved.", flash[:notice]
    pref = @user.user_preferences.find_by(key: "trades_index_visible_columns:history")
    assert pref, "expected preference key trades_index_visible_columns:history"
    assert_equal %w[closed symbol side], pref.value
  end

  test "update_trades_index_columns with empty selection redirects back with alert" do
    sign_in_as(@user)
    patch user_preferences_trades_index_columns_path, params: { column_ids: [] }
    assert_redirected_to trades_path
    assert_equal "Select at least one column.", flash[:alert]
  end

  test "update_trades_index_columns ignores invalid column ids" do
    sign_in_as(@user)
    patch user_preferences_trades_index_columns_path, params: { view: "history", column_ids: %w[symbol invalid_id side] }
    assert_redirected_to trades_path(view: "history")
    pref = @user.user_preferences.find_by(key: "trades_index_visible_columns:history")
    assert_equal %w[symbol side], pref.value
  end

  test "update_trades_index_columns saves per exchange tab" do
    sign_in_as(@user)
    account = exchange_accounts(:one)
    patch user_preferences_trades_index_columns_path, params: {
      view: "exchange",
      exchange_account_id: account.id,
      column_ids: %w[symbol side balance]
    }
    assert_redirected_to trades_path(view: "exchange", exchange_account_id: account.id.to_s)
    assert_equal "Columns saved.", flash[:notice]
    pref = @user.user_preferences.find_by(key: "trades_index_visible_columns:exchange:#{account.id}")
    assert pref, "expected preference key for exchange tab"
    assert_equal %w[symbol side balance], pref.value
  end

  test "update_trades_index_columns saves per portfolio tab" do
    sign_in_as(@user)
    portfolio = portfolios(:one)
    patch user_preferences_trades_index_columns_path, params: {
      view: "portfolio",
      portfolio_id: portfolio.id,
      column_ids: %w[symbol side balance]
    }
    assert_redirected_to trades_path(view: "portfolio", portfolio_id: portfolio.id.to_s)
    assert_equal "Columns saved.", flash[:notice]
    pref = @user.user_preferences.find_by(key: "trades_index_visible_columns:portfolio:#{portfolio.id}")
    assert pref, "expected preference key for portfolio tab"
    assert_equal %w[symbol side balance], pref.value
  end

  test "update_trades_index_columns with foreign exchange_account_id redirects with alert and does not save" do
    sign_in_as(@user)
    other_account = exchange_accounts(:two) # belongs to user two
    patch user_preferences_trades_index_columns_path, params: {
      view: "exchange",
      exchange_account_id: other_account.id,
      column_ids: %w[symbol side]
    }
    assert_redirected_to trades_path
    assert_match(/Exchange account not found/i, flash[:alert].to_s)
    pref = @user.user_preferences.find_by(key: "trades_index_visible_columns:exchange:#{other_account.id}")
    assert_nil pref, "must not save preference for another user's exchange account"
  end

  test "update_trades_index_columns with non-existent portfolio_id redirects with alert and does not save" do
    sign_in_as(@user)
    patch user_preferences_trades_index_columns_path, params: {
      view: "portfolio",
      portfolio_id: 999999,
      column_ids: %w[symbol side]
    }
    assert_redirected_to trades_path
    assert_match(/Portfolio not found/i, flash[:alert].to_s)
    assert_nil @user.user_preferences.find_by(key: "trades_index_visible_columns:portfolio:999999"),
      "must not save preference for non-existent portfolio"
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
