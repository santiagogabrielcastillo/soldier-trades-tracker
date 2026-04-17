# frozen_string_literal: true

require "test_helper"

class UserApiKeyTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "key_for returns key string when row exists" do
    @user.user_api_keys.create!(provider: "finnhub", key: "abc123")
    assert_equal "abc123", UserApiKey.key_for(@user, :finnhub)
  end

  test "key_for returns nil when no row" do
    assert_nil UserApiKey.key_for(@user, :finnhub)
  end

  test "credentials_for returns hash with key and secret" do
    @user.user_api_keys.create!(provider: "iol", key: "user@example.com", secret: "pass")
    result = UserApiKey.credentials_for(@user, :iol)
    assert_equal "user@example.com", result[:key]
    assert_equal "pass", result[:secret]
  end

  test "credentials_for returns nil when no row" do
    assert_nil UserApiKey.credentials_for(@user, :iol)
  end

  test "api_key_for on user returns the row" do
    row = @user.user_api_keys.create!(provider: "coingecko", key: "cg_key")
    assert_equal row, @user.api_key_for(:coingecko)
  end

  test "api_key_for returns nil when not configured" do
    assert_nil @user.api_key_for(:coingecko)
  end

  test "provider uniqueness per user" do
    @user.user_api_keys.create!(provider: "finnhub", key: "first")
    duplicate = @user.user_api_keys.build(provider: "finnhub", key: "second")
    assert_not duplicate.valid?
  end

  test "key is encrypted at rest" do
    row = @user.user_api_keys.create!(provider: "finnhub", key: "secret_key")
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT key FROM user_api_keys WHERE id = #{row.id}"
    )
    assert_not_equal "secret_key", raw
  end
end
