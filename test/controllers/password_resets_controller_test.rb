# frozen_string_literal: true

require "test_helper"

class PasswordResetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password")
    ActionMailer::Base.deliveries.clear
  end

  # --- new ---

  test "GET new renders the form" do
    get new_password_reset_path
    assert_response :ok
  end

  # --- create ---

  test "POST create with known active email enqueues reset email" do
    assert_difference "ActionMailer::Base.deliveries.count", 1 do
      post password_reset_path, params: { email: @user.email }
    end
  end

  test "POST create redirects to login with generic notice regardless of email" do
    post password_reset_path, params: { email: @user.email }
    assert_redirected_to login_path
    assert_match "If that email is registered", flash[:notice]
  end

  test "POST create with unknown email still redirects with same generic notice (no enumeration)" do
    post password_reset_path, params: { email: "nobody@example.com" }
    assert_redirected_to login_path
    assert_match "If that email is registered", flash[:notice]
  end

  test "POST create with unknown email does not send an email" do
    assert_no_difference "ActionMailer::Base.deliveries.count" do
      post password_reset_path, params: { email: "nobody@example.com" }
    end
  end

  test "POST create with inactive user does not send an email" do
    inactive = users(:inactive)
    assert_no_difference "ActionMailer::Base.deliveries.count" do
      post password_reset_path, params: { email: inactive.email }
    end
  end

  # --- edit ---

  test "GET edit with valid token renders the form" do
    token = @user.generate_token_for(:password_reset)
    get edit_password_reset_path(token: token)
    assert_response :ok
  end

  test "GET edit with invalid token redirects to new with alert" do
    get edit_password_reset_path(token: "invalid")
    assert_redirected_to new_password_reset_path
    assert_match "invalid or has expired", flash[:alert]
  end

  test "GET edit with expired token redirects to new with alert" do
    token = @user.generate_token_for(:password_reset)
    travel 2.hours + 1.second do
      get edit_password_reset_path(token: token)
    end
    assert_redirected_to new_password_reset_path
    assert_match "invalid or has expired", flash[:alert]
  end

  # --- update ---

  test "PATCH update with valid token and matching passwords resets the password" do
    token = @user.generate_token_for(:password_reset)
    patch password_reset_path, params: { token: token, password: "newpass123", password_confirmation: "newpass123" }
    assert_redirected_to login_path
    assert_match "Password updated", flash[:notice]
    assert @user.reload.authenticate("newpass123"), "Password should have been updated"
  end

  test "PATCH update invalidates the token after use" do
    token = @user.generate_token_for(:password_reset)
    patch password_reset_path, params: { token: token, password: "newpass123", password_confirmation: "newpass123" }
    # Token no longer valid because password_digest changed
    assert_nil User.find_by_token_for(:password_reset, token)
  end

  test "PATCH update with mismatched passwords re-renders edit" do
    token = @user.generate_token_for(:password_reset)
    patch password_reset_path, params: { token: token, password: "newpass123", password_confirmation: "different" }
    assert_response :unprocessable_entity
  end

  test "PATCH update with invalid token redirects to new with alert" do
    patch password_reset_path, params: { token: "invalid", password: "newpass123", password_confirmation: "newpass123" }
    assert_redirected_to new_password_reset_path
    assert_match "invalid or has expired", flash[:alert]
  end
end
