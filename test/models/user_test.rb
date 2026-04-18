# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "role defaults to user" do
    user = User.new(email: "test@example.com", password: "password")
    assert_predicate user, :user?
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

  test "admin? returns true for admin role" do
    assert_predicate users(:admin), :admin?
  end

  test "super_admin? returns true for super_admin role" do
    assert_predicate users(:super_admin), :super_admin?
  end

  test "last active super_admin cannot be deactivated" do
    super_admin = users(:super_admin)
    super_admin.update!(password: "password", password_confirmation: "password")

    result = super_admin.update(active: false)
    assert_not result
    assert_includes super_admin.errors[:active], "cannot deactivate the last active super admin"
    assert_predicate super_admin.reload, :active?
  end

  test "super_admin can be deactivated when another active super_admin exists" do
    super_admin = users(:super_admin)
    super_admin.update!(password: "password", password_confirmation: "password")

    second = User.create!(email: "second_sa@example.com", password: "password",
                          password_confirmation: "password", role: "super_admin", active: true)

    result = super_admin.update(active: false)
    assert result, "Should allow deactivating when another active super_admin exists"
    assert_not super_admin.reload.active?
  ensure
    second.destroy
    super_admin.update_columns(active: true)
  end

  test "admin can be deactivated freely" do
    admin = users(:admin)
    admin.update!(password: "password", password_confirmation: "password")

    result = admin.update(active: false)
    assert result, "Admins should be deactivatable regardless of other admins"
  ensure
    admin.update_columns(active: true)
  end

  test "api_key_for returns nil when no key for provider" do
    user = users(:one)
    assert_nil user.api_key_for(:gemini)
  end

  test "api_key_for returns the UserApiKey record when present" do
    user = users(:one)
    user.user_api_keys.create!(provider: "gemini", key: "AIzaSyTestKey12345678")
    assert_not_nil user.api_key_for(:gemini)
  end

  test "generates a password reset token" do
    user = users(:one)
    user.update!(password: "password")
    token = user.generate_token_for(:password_reset)
    assert_not_nil token
    assert_equal user, User.find_by_token_for(:password_reset, token)
  end

  test "password reset token expires after 2 hours" do
    user = users(:one)
    user.update!(password: "password")
    token = user.generate_token_for(:password_reset)

    travel 2.hours + 1.second do
      assert_nil User.find_by_token_for(:password_reset, token)
    end
  end

  test "password reset token is invalidated after password change" do
    user = users(:one)
    user.update!(password: "oldpassword")
    token = user.generate_token_for(:password_reset)

    user.update!(password: "newpassword", password_confirmation: "newpassword")
    assert_nil User.find_by_token_for(:password_reset, token)
  end
end
