# frozen_string_literal: true

require "test_helper"

class ExchangeAccountTest < ActiveSupport::TestCase
  def build_account(overrides = {})
    ExchangeAccount.new(
      { user: users(:one), provider_type: "bingx", api_key: "k", api_secret: "s" }.merge(overrides)
    )
  end

  # --- Default getter ---

  test "allowed_quote_currencies returns default when settings is empty" do
    account = build_account
    assert_equal %w[USDT USDC], account.allowed_quote_currencies
  end

  test "allowed_quote_currencies returns stored value when explicitly set" do
    account = build_account
    account.settings = { "allowed_quote_currencies" => [ "USDT" ] }
    assert_equal [ "USDT" ], account.allowed_quote_currencies
  end

  test "allowed_quote_currencies default does not dirty the record" do
    account = exchange_accounts(:one)
    account.reload
    _ = account.allowed_quote_currencies
    assert_not account.settings_changed?, "Reading allowed_quote_currencies should not dirty settings"
  end

  # --- Normalization ---

  test "saves allowed_quote_currencies upcased when lowercase is provided" do
    account = build_account
    account.settings = { "allowed_quote_currencies" => [ "usdt", "usdc" ] }
    account.valid?
    assert_equal %w[USDT USDC], account.settings["allowed_quote_currencies"]
  end

  test "deduplicates allowed_quote_currencies on save" do
    account = build_account
    account.settings = { "allowed_quote_currencies" => [ "USDT", "usdt", "USDC" ] }
    account.valid?
    assert_equal %w[USDT USDC], account.settings["allowed_quote_currencies"]
  end

  # --- Validations ---

  test "is valid with default settings (no allowed_quote_currencies key)" do
    account = build_account
    account.valid?
    assert account.errors[:allowed_quote_currencies].empty?
  end

  test "is valid with explicit USDT only" do
    account = build_account
    account.settings = { "allowed_quote_currencies" => [ "USDT" ] }
    account.valid?
    assert account.errors[:allowed_quote_currencies].empty?
  end

  test "is valid with USDT and USDC" do
    account = build_account
    account.settings = { "allowed_quote_currencies" => %w[USDT USDC] }
    account.valid?
    assert account.errors[:allowed_quote_currencies].empty?
  end

  test "is invalid when allowed_quote_currencies is an empty array" do
    account = build_account
    account.settings = { "allowed_quote_currencies" => [] }
    account.valid?
    assert_includes account.errors[:allowed_quote_currencies].join, "at least one currency"
  end

  test "is invalid when allowed_quote_currencies is a string instead of array" do
    account = build_account
    account.settings = { "allowed_quote_currencies" => "USDT" }
    account.valid?
    assert_includes account.errors[:allowed_quote_currencies].join, "must be an array"
  end

  test "is invalid with an unknown currency" do
    account = build_account
    account.settings = { "allowed_quote_currencies" => [ "BTC" ] }
    account.valid?
    assert_includes account.errors[:allowed_quote_currencies].join, "BTC"
  end

  test "BUSD is a valid (legacy) currency" do
    account = build_account
    account.settings = { "allowed_quote_currencies" => [ "BUSD" ] }
    account.valid?
    assert account.errors[:allowed_quote_currencies].empty?
  end
end
