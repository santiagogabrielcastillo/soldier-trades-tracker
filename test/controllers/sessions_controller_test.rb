# frozen_string_literal: true

require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
  end

  test "login sets user_id in session" do
    post login_url, params: { email: @user.email, password: "password" }
    assert_equal @user.id, session[:user_id]
    assert_redirected_to root_url
  end

  test "login works with mixed-case email" do
    post login_url, params: { email: @user.email.upcase, password: "password" }
    assert_equal @user.id, session[:user_id]
    assert_redirected_to root_url
  end

  test "inactive user cannot log in" do
    inactive = users(:inactive)
    inactive.update!(password: "password", password_confirmation: "password")

    post login_url, params: { email: inactive.email, password: "password" }
    assert_nil session[:user_id]
    assert_response :unprocessable_entity
  end

  test "inactive user login shows generic error (no enumeration)" do
    inactive = users(:inactive)
    inactive.update!(password: "password", password_confirmation: "password")

    post login_url, params: { email: inactive.email, password: "password" }
    assert_match "Invalid email or password", flash[:alert]
  end

  test "logout clears entire session" do
    post login_url, params: { email: @user.email, password: "password" }
    assert_equal @user.id, session[:user_id]

    delete logout_url
    assert_nil session[:user_id]
    assert_redirected_to login_url
  end

  test "failed login does not set user_id" do
    post login_url, params: { email: @user.email, password: "wrong" }
    assert_nil session[:user_id]
    assert_response :unprocessable_entity
  end

  test "login regenerates session id" do
    get login_url  # establish a pre-auth session
    pre_login_cookie = cookies["_soldier_trades_tracker_session"]

    post login_url, params: { email: @user.email, password: "password" }
    assert_not_equal pre_login_cookie, cookies["_soldier_trades_tracker_session"],
      "Session ID must change on login to prevent session fixation"
  end

  test "logout regenerates session id" do
    post login_url, params: { email: @user.email, password: "password" }
    logged_in_cookie = cookies["_soldier_trades_tracker_session"]

    delete logout_url
    assert_not_equal logged_in_cookie, cookies["_soldier_trades_tracker_session"],
      "Session ID must change on logout"
  end
end
