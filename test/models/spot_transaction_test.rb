# frozen_string_literal: true

require "test_helper"

class SpotTransactionTest < ActiveSupport::TestCase
  setup do
    @spot_account = spot_accounts(:one)
  end

  test "valid with required attributes" do
    tx = SpotTransaction.new(
      spot_account: @spot_account,
      executed_at: Time.current,
      token: "BTC",
      side: "buy",
      price_usd: 50000,
      amount: 0.01,
      total_value_usd: 500,
      row_signature: "unique_sig_#{SecureRandom.hex(8)}"
    )
    assert tx.valid?
  end

  test "invalid without row_signature" do
    tx = SpotTransaction.new(
      spot_account: @spot_account,
      executed_at: Time.current,
      token: "BTC",
      side: "buy",
      price_usd: 50000,
      amount: 0.01,
      total_value_usd: 500,
      row_signature: nil
    )
    assert_not tx.valid?
    assert_includes tx.errors[:row_signature], "can't be blank"
  end

  test "invalid with duplicate row_signature in same spot_account" do
    SpotTransaction.create!(
      spot_account: @spot_account,
      executed_at: Time.current,
      token: "BTC",
      side: "buy",
      price_usd: 50000,
      amount: 0.01,
      total_value_usd: 500,
      row_signature: "dup_sig"
    )
    tx = SpotTransaction.new(
      spot_account: @spot_account,
      executed_at: Time.current,
      token: "BTC",
      side: "sell",
      price_usd: 51000,
      amount: 0.01,
      total_value_usd: 510,
      row_signature: "dup_sig"
    )
    assert_not tx.valid?
    assert_includes tx.errors[:row_signature], "has already been taken"
  end

  test "side must be buy sell deposit or withdraw" do
    tx = SpotTransaction.new(
      spot_account: @spot_account,
      executed_at: Time.current,
      token: "BTC",
      side: "swap",
      price_usd: 50000,
      amount: 0.01,
      total_value_usd: 500,
      row_signature: "sig_swap"
    )
    assert_not tx.valid?
    assert_includes tx.errors[:side], "is not included in the list"
  end

  test "valid with side deposit" do
    tx = SpotTransaction.new(
      spot_account: @spot_account,
      executed_at: Time.current,
      token: "USDT",
      side: "deposit",
      price_usd: 1,
      amount: 100,
      total_value_usd: 100,
      row_signature: "cash|#{Time.current.to_i}|#{SecureRandom.hex(8)}"
    )
    assert tx.valid?
  end

  test "scope trades returns only buy and sell" do
    @spot_account.spot_transactions.destroy_all
    @spot_account.spot_transactions.create!(
      executed_at: Time.current,
      token: "USDT",
      side: "deposit",
      price_usd: 1,
      amount: 100,
      total_value_usd: 100,
      row_signature: "cash|#{Time.current.to_i}|#{SecureRandom.hex(8)}"
    )
    @spot_account.spot_transactions.create!(
      executed_at: Time.current,
      token: "BTC",
      side: "buy",
      price_usd: 50000,
      amount: 0.01,
      total_value_usd: 500,
      row_signature: "buy_sig_#{SecureRandom.hex(8)}"
    )
    assert_equal 1, @spot_account.spot_transactions.trades.count
    assert_equal "buy", @spot_account.spot_transactions.trades.first.side
  end
end
