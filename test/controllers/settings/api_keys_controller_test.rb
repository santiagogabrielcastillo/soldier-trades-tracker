# frozen_string_literal: true

require "test_helper"

module Settings
  class ApiKeysControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @user.update!(password: "password", password_confirmation: "password")
      post login_path, params: { email: @user.email, password: "password" }
    end

    test "index lists all providers" do
      get settings_api_keys_path
      assert_response :success
      assert_select "body", /Finnhub/
      assert_select "body", /CoinGecko/
      assert_select "body", /IOL/
      assert_select "body", /Anthropic/
      assert_select "body", /Gemini/
    end

    test "upsert creates a key" do
      assert_difference "UserApiKey.count" do
        post upsert_settings_api_keys_path, params: { provider: "finnhub", key: "abc123" }
      end
      assert_redirected_to settings_api_keys_path
      assert_equal "abc123", UserApiKey.key_for(@user, :finnhub)
    end

    test "upsert updates existing key" do
      @user.user_api_keys.create!(provider: "finnhub", key: "old")
      assert_no_difference "UserApiKey.count" do
        post upsert_settings_api_keys_path, params: { provider: "finnhub", key: "new" }
      end
      assert_equal "new", UserApiKey.key_for(@user, :finnhub)
    end

    test "upsert stores key and secret for iol" do
      post upsert_settings_api_keys_path, params: { provider: "iol", key: "user@example.com", secret: "pass" }
      creds = UserApiKey.credentials_for(@user, :iol)
      assert_equal "user@example.com", creds[:key]
      assert_equal "pass", creds[:secret]
    end

    test "upsert rejects blank key" do
      assert_no_difference "UserApiKey.count" do
        post upsert_settings_api_keys_path, params: { provider: "finnhub", key: "" }
      end
      assert_redirected_to settings_api_keys_path
    end

    test "destroy removes the key" do
      @user.user_api_keys.create!(provider: "finnhub", key: "abc")
      assert_difference "UserApiKey.count", -1 do
        delete settings_api_key_path("finnhub")
      end
      assert_redirected_to settings_api_keys_path
    end

    test "destroy for unknown provider does not raise" do
      delete settings_api_key_path("finnhub")
      assert_redirected_to settings_api_keys_path
    end
  end
end
