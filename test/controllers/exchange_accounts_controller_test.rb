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

  test "create with binance provider succeeds when ping returns true" do
    sign_in_as(@user)
    Exchanges::ProviderForAccount.stub(:ping?, true) do
      post exchange_accounts_path, params: {
        exchange_account: {
          provider_type: "binance",
          api_key: "binance_key",
          api_secret: "binance_secret"
        }
      }
    end
    assert_redirected_to exchange_accounts_path
    assert_equal "Exchange account linked successfully.", flash[:notice]
    account = @user.exchange_accounts.find_by(provider_type: "binance")
    assert account
    assert account.api_key.present?
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
