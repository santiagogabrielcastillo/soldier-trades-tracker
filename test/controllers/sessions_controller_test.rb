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
end
