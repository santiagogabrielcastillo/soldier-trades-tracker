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
  end

  test "update_ai_key saves the API key" do
    patch settings_ai_key_path, params: { api_key: "AIzaNewKey12345678" }
    assert_redirected_to settings_path
    @user.reload
    assert_equal "AIzaNewKey12345678", @user.gemini_api_key
  end

  test "remove_ai_key clears the API key" do
    @user.update!(gemini_api_key: "AIzaExistingKey1234")
    delete settings_ai_key_path
    assert_redirected_to settings_path
    @user.reload
    assert_nil @user.gemini_api_key
  end

  test "update_ai_key requires authentication" do
    delete logout_path
    patch settings_ai_key_path, params: { api_key: "AIzaNewKey12345678" }
    assert_response :redirect
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
