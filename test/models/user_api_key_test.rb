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
    sql = ActiveRecord::Base.sanitize_sql_array([ "SELECT key FROM user_api_keys WHERE id = ?", row.id ])
    raw = ActiveRecord::Base.connection.select_value(sql)
    assert_not_equal "secret_key", raw
  end

  test "rejects invalid provider" do
    record = @user.user_api_keys.build(provider: "unknown_service", key: "abc")
    assert_not record.valid?
    assert_includes record.errors[:provider], "is not included in the list"
  end

  test "two different users can hold the same provider" do
    user2 = users(:two)
    @user.user_api_keys.create!(provider: "finnhub", key: "key1")
    record = user2.user_api_keys.build(provider: "finnhub", key: "key2")
    assert record.valid?
  end
end
