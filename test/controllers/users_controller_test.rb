# frozen_string_literal: true

require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Ensure a valid invite code exists for all tests
    InviteCode.delete_all
    @invite = InviteCode.create!(code: "testinvitecode12345678901234567", expires_at: 1.day.from_now)
  end

  teardown do
    InviteCode.delete_all
  end

  test "registration creates user and logs them in" do
    post users_url, params: {
      user: { email: "new@example.com", password: "password123", password_confirmation: "password123" },
      invite_code: @invite.code
    }
    new_user = User.find_by(email: "new@example.com")
    assert new_user
    assert_equal new_user.id, session[:user_id]
    assert_redirected_to root_url
  end

  test "registration normalizes email to lowercase" do
    post users_url, params: {
      user: { email: "New@Example.COM", password: "password123", password_confirmation: "password123" },
      invite_code: @invite.code
    }
    assert User.find_by(email: "new@example.com"), "Email should be stored lowercase"
  end

  test "registration regenerates session id" do
    get new_user_url
    pre_reg_cookie = cookies["_soldier_trades_tracker_session"]

    post users_url, params: {
      user: { email: "new2@example.com", password: "password123", password_confirmation: "password123" },
      invite_code: @invite.code
    }
    assert_not_equal pre_reg_cookie, cookies["_soldier_trades_tracker_session"],
      "Session ID must change on registration to prevent session fixation"
  end

  test "registration blocked when invite code is wrong" do
    post users_url, params: {
      user: { email: "blocked@example.com", password: "password123", password_confirmation: "password123" },
      invite_code: "wrongcode"
    }
    assert_response :unprocessable_entity
    assert_nil User.find_by(email: "blocked@example.com")
  end

  test "registration blocked when invite code is expired" do
    @invite.update_columns(expires_at: 1.day.ago)

    post users_url, params: {
      user: { email: "blocked2@example.com", password: "password123", password_confirmation: "password123" },
      invite_code: @invite.code
    }
    assert_response :unprocessable_entity
    assert_nil User.find_by(email: "blocked2@example.com")
  end

  test "registration blocked when no invite code exists" do
    InviteCode.delete_all

    post users_url, params: {
      user: { email: "blocked3@example.com", password: "password123", password_confirmation: "password123" },
      invite_code: "anycode"
    }
    assert_response :unprocessable_entity
    assert_nil User.find_by(email: "blocked3@example.com")
  end

  test "registration blocked when invite code param is blank" do
    post users_url, params: {
      user: { email: "blocked4@example.com", password: "password123", password_confirmation: "password123" },
      invite_code: ""
    }
    assert_response :unprocessable_entity
    assert_nil User.find_by(email: "blocked4@example.com")
  end

  test "new user is active by default" do
    post users_url, params: {
      user: { email: "newactive@example.com", password: "password123", password_confirmation: "password123" },
      invite_code: @invite.code
    }
    new_user = User.find_by(email: "newactive@example.com")
    assert new_user.active?, "Newly registered user should be active"
  end
end
