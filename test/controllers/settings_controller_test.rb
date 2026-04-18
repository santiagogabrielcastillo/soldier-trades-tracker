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
    assert_select "span", text: "AI Assistant"
  end

  test "show displays key entry form when no API key configured" do
    @user.user_api_keys.where(provider: "gemini").destroy_all
    get settings_path
    assert_response :success
    assert_select "input[name='api_key']"
  end

  test "show displays masked key and actions when API key is configured" do
    @user.user_api_keys.find_or_create_by!(provider: "gemini") { |r| r.key = "AIzaTestKey12345678" }
    get settings_path
    assert_response :success
    assert_match "AIza", response.body
    assert_select "button", text: "Test Connection"
  end

  test "update_ai_key saves the API key" do
    patch settings_ai_key_path, params: { api_key: "AIzaNewKey12345678" }
    assert_redirected_to settings_path
    @user.reload
    assert_equal "AIzaNewKey12345678", UserApiKey.key_for(@user, :gemini)
  end

  test "remove_ai_key clears the API key" do
    @user.user_api_keys.find_or_create_by!(provider: "gemini") { |r| r.key = "AIzaExistingKey1234" }
    delete remove_settings_ai_key_path
    assert_redirected_to settings_path
    assert_nil UserApiKey.key_for(@user, :gemini)
  end

  test "update_ai_key requires authentication" do
    delete logout_path
    patch settings_ai_key_path, params: { api_key: "AIzaNewKey12345678" }
    assert_response :redirect
  end

  # ── Deep Analysis (Claude) card ───────────────────────────────────────────

  test "shows Deep Analysis card as active when user has anthropic key configured" do
    @user.user_api_keys.find_or_create_by!(provider: "anthropic") { |r| r.key = "sk-ant-platform" }
    get settings_path
    assert_response :success
    assert_select "span", text: /Active · Powered by Claude/
  ensure
    @user.user_api_keys.where(provider: "anthropic").destroy_all
  end

  test "shows Deep Analysis card as inactive when no anthropic key" do
    @user.user_api_keys.where(provider: "anthropic").destroy_all
    get settings_path
    assert_response :success
    assert_select "span", text: "Deep Analysis"
    assert_match /not\s+currently\s+enabled/, response.body
  end

  test "Deep Analysis card always renders regardless of Gemini key status" do
    @user.user_api_keys.where(provider: "gemini").destroy_all
    @user.user_api_keys.where(provider: "anthropic").destroy_all
    get settings_path
    assert_response :success
    assert_select "span", text: "Deep Analysis"
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
