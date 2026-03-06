# frozen_string_literal: true

require "test_helper"

class UserPreferenceTest < ActiveSupport::TestCase
  test "valid with user, key, and value" do
    pref = UserPreference.new(user: users(:one), key: "trades_index_visible_columns", value: %w[symbol side])
    assert pref.valid?, pref.errors.full_messages.join(", ")
  end

  test "invalid without key" do
    pref = UserPreference.new(user: users(:one), key: nil, value: %w[symbol])
    refute pref.valid?
    assert_includes pref.errors[:key], "can't be blank"
  end

  test "invalid with blank value" do
    pref = UserPreference.new(user: users(:one), key: "trades_index_visible_columns", value: [])
    refute pref.valid?
    assert pref.errors[:value].present?
  end

  test "uniqueness of key scoped to user" do
    user = users(:one)
    UserPreference.create!(user: user, key: "trades_index_visible_columns", value: %w[symbol])
    dup = UserPreference.new(user: user, key: "trades_index_visible_columns", value: %w[side])
    refute dup.valid?
    assert_includes dup.errors[:key], "has already been taken"
  end
end
