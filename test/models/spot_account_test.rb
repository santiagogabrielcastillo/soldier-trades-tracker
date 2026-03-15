# frozen_string_literal: true

require "test_helper"

class SpotAccountTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "find_or_create_default_for creates default spot account when none exist" do
    @user.spot_accounts.destroy_all
    account = SpotAccount.find_or_create_default_for(@user)
    assert account.persisted?
    assert_equal "Default", account.name
    assert account.default?
    assert_equal @user.id, account.user_id
  end

  test "find_or_create_default_for returns existing default" do
    existing = @user.spot_accounts.create!(name: "Default", default: true)
    account = SpotAccount.find_or_create_default_for(@user)
    assert_equal existing.id, account.id
  end

  test "clear_other_defaults sets other accounts to non-default when setting default" do
    a1 = @user.spot_accounts.create!(name: "A1", default: true)
    a2 = @user.spot_accounts.create!(name: "A2", default: false)
    a2.update!(default: true)
    assert a2.reload.default?
    assert_not a1.reload.default?
  end

  test "cash_balance is deposits minus withdrawals" do
    account = @user.spot_accounts.create!(name: "Default", default: true)
    account.spot_transactions.create!(
      executed_at: Time.current,
      token: "USDT",
      side: "deposit",
      price_usd: 1,
      amount: 500,
      total_value_usd: 500,
      row_signature: "cash|#{Time.current.to_i}|#{SecureRandom.hex(8)}"
    )
    account.spot_transactions.create!(
      executed_at: 1.hour.from_now,
      token: "USDT",
      side: "withdraw",
      price_usd: 1,
      amount: 100,
      total_value_usd: 100,
      row_signature: "cash|#{1.hour.from_now.to_i}|#{SecureRandom.hex(8)}"
    )
    assert_equal 400, account.cash_balance.to_i
  end

  test "cash_balance is zero when no cash movements" do
    account = @user.spot_accounts.create!(name: "Default", default: true)
    assert_equal 0, account.cash_balance.to_i
  end
end
