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
end
