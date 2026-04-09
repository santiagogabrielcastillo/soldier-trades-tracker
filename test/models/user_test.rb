# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "admin defaults to false" do
    user = User.new(email: "test@example.com", password: "password")
    assert_equal false, user.admin
  end

  test "active defaults to true" do
    user = User.new(email: "test@example.com", password: "password")
    assert_equal true, user.active
  end

  test "email is normalized to lowercase on save" do
    user = User.create!(email: "Test@EXAMPLE.COM", password: "password", password_confirmation: "password")
    assert_equal "test@example.com", user.email
  end

  test "email strips whitespace on save" do
    user = User.create!(email: "  test2@example.com  ", password: "password", password_confirmation: "password")
    assert_equal "test2@example.com", user.email
  end

  test "active scope returns only active users" do
    active_user = users(:one)
    inactive_user = users(:inactive)
    scoped = User.active
    assert_includes scoped, active_user
    assert_not_includes scoped, inactive_user
  end

  test "last active admin cannot be deactivated" do
    admin = users(:admin)
    admin.update!(password: "password", password_confirmation: "password")

    result = admin.update(active: false)
    assert_not result
    assert_includes admin.errors[:active], "cannot deactivate the last active admin"
    assert admin.reload.active?, "Admin should still be active in DB"
  end

  test "admin can be deactivated when another active admin exists" do
    admin = users(:admin)
    admin.update!(password: "password", password_confirmation: "password")

    # Create a second admin
    second_admin = User.create!(email: "second_admin@example.com", password: "password",
                                password_confirmation: "password", admin: true, active: true)

    result = admin.update(active: false)
    assert result, "Should allow deactivating an admin when another active admin exists"
    assert_not admin.reload.active?

    second_admin.destroy
  end

  test "gemini_api_key_configured? returns false when key is nil" do
    user = User.new(email: "ai@example.com", password: "password")
    assert_equal false, user.gemini_api_key_configured?
  end

  test "gemini_api_key_configured? returns true when key is set" do
    user = users(:one)
    user.gemini_api_key = "AIzaSyTestKey12345678"
    assert_equal true, user.gemini_api_key_configured?
  end

  test "gemini_api_key_masked returns nil when key is blank" do
    user = User.new(email: "ai@example.com", password: "password")
    assert_nil user.gemini_api_key_masked
  end

  test "gemini_api_key_masked returns masked string when key is set" do
    user = users(:one)
    user.gemini_api_key = "AIzaSyTestKey12345678"
    assert_equal "AIza...5678", user.gemini_api_key_masked
  end
end
