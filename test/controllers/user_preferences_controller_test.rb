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

  test "update_trades_index_columns saves preference and redirects to trades" do
    sign_in_as(@user)
    patch user_preferences_trades_index_columns_path, params: { column_ids: %w[closed symbol side] }
    assert_redirected_to trades_path
    assert_equal "Columns saved.", flash[:notice]
    pref = @user.user_preferences.find_by(key: "trades_index_visible_columns")
    assert pref
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
    patch user_preferences_trades_index_columns_path, params: { column_ids: %w[symbol invalid_id side] }
    assert_redirected_to trades_path
    pref = @user.user_preferences.find_by(key: "trades_index_visible_columns")
    assert_equal %w[symbol side], pref.value
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
