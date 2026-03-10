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

  test "side must be buy or sell" do
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
end
