# frozen_string_literal: true

require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    sign_in_as(@user)
  end

  test "show renders successfully" do
    get settings_path
    assert_response :success
    assert_select "h1", text: "Settings"
  end

  test "show displays link to manage API keys" do
    get settings_path
    assert_response :success
    assert_select "a", text: "Manage API Keys"
  end

  test "update saves sync interval" do
    patch settings_path, params: { user: { sync_interval: "daily" } }
    assert_redirected_to settings_path
    assert_equal "daily", @user.reload.sync_interval
  end

  test "update requires authentication" do
    delete logout_path
    patch settings_path, params: { user: { sync_interval: "daily" } }
    assert_response :redirect
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
