# frozen_string_literal: true

require "test_helper"

class ExchangeAccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
  end

  test "new returns 200 and shows exchange select" do
    sign_in_as(@user)
    get new_exchange_account_path
    assert_response :success
    assert_match(/Link exchange account/, response.body)
    assert_select "select[name=?]", "exchange_account[provider_type]"
    assert_match(/Binance|BingX/, response.body)
  end

  test "create with binance provider succeeds without requiring read-only ping" do
    sign_in_as(@user)
    post exchange_accounts_path, params: {
      exchange_account: {
        provider_type: "binance",
        api_key: "binance_key",
        api_secret: "binance_secret"
      }
    }
    assert_redirected_to exchange_accounts_path
    account = @user.exchange_accounts.find_by(provider_type: "binance")
    assert account
    assert account.api_key.present?
  end

  test "create with bingx provider succeeds without requiring read-only ping" do
    sign_in_as(@user)
    post exchange_accounts_path, params: {
      exchange_account: {
        provider_type: "bingx",
        api_key: "bingx_key",
        api_secret: "bingx_secret"
      }
    }
    assert_redirected_to exchange_accounts_path
    account = @user.exchange_accounts.find_by(provider_type: "bingx")
    assert account
  end

  test "create fails when api_key is blank" do
    sign_in_as(@user)
    post exchange_accounts_path, params: {
      exchange_account: { provider_type: "bingx", api_key: "", api_secret: "secret" }
    }
    assert_response :unprocessable_entity
  end

  test "create shows info flash when user links their first account" do
    sign_in_as(@user)
    # ensure this user has no accounts yet
    @user.exchange_accounts.destroy_all
    post exchange_accounts_path, params: {
      exchange_account: { provider_type: "bingx", api_key: "k", api_secret: "s" }
    }
    assert_redirected_to exchange_accounts_path
    follow_redirect!
    assert_match(/admin/i, response.body)
    assert_match(/historic/i, response.body)
  end

  test "create shows standard notice flash when user already has accounts" do
    sign_in_as(@user)
    # ensure clean slate then create a pre-existing account (avoids fixture encryption issues)
    @user.exchange_accounts.destroy_all
    @user.exchange_accounts.create!(provider_type: "bingx", api_key: "existing", api_secret: "existing", linked_at: 1.day.ago)
    post exchange_accounts_path, params: {
      exchange_account: { provider_type: "binance", api_key: "k2", api_secret: "s2" }
    }
    assert_redirected_to exchange_accounts_path
    follow_redirect!
    assert_match(/linked successfully/i, response.body)
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
