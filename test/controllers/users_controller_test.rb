# frozen_string_literal: true

require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["REGISTRATION_OPEN"] = "true"
  end

  teardown do
    ENV.delete("REGISTRATION_OPEN")
  end

  test "registration creates user and logs them in" do
    post users_url, params: {
      user: { email: "new@example.com", password: "password123", password_confirmation: "password123" }
    }
    new_user = User.find_by(email: "new@example.com")
    assert new_user
    assert_equal new_user.id, session[:user_id]
    assert_redirected_to root_url
  end

  test "registration regenerates session id" do
    get new_user_url  # establish pre-registration session
    pre_reg_cookie = cookies["_soldier_trades_tracker_session"]

    post users_url, params: {
      user: { email: "new2@example.com", password: "password123", password_confirmation: "password123" }
    }
    assert_not_equal pre_reg_cookie, cookies["_soldier_trades_tracker_session"],
      "Session ID must change on registration to prevent session fixation"
  end

  test "registration blocked when REGISTRATION_OPEN is false" do
    ENV["REGISTRATION_OPEN"] = "false"
    post users_url, params: {
      user: { email: "blocked@example.com", password: "password123", password_confirmation: "password123" }
    }
    assert_response :not_found
    assert_nil User.find_by(email: "blocked@example.com")
  end
end
