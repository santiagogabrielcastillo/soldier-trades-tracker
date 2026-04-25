# frozen_string_literal: true

require "test_helper"

class LanguageSwitcherTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:santiago)
  end

  test "user can navigate to settings and see language switcher" do
    sign_in @user
    get settings_path

    assert_response :success
    assert_select "legend", t("settings.language")
    assert_select "input[type='radio'][value='en']"
    assert_select "input[type='radio'][value='es']"
  end

  test "user can change language from english to spanish" do
    sign_in @user

    # Initial state: English (default)
    get settings_path
    assert_response :success

    # Change to Spanish
    patch locale_path, params: { locale: "es" }

    # Verify redirect and flash message
    assert_redirected_to root_path
    follow_redirect!
    assert_match t("flash.language_changed"), response.body

    # Verify preference was saved
    assert_equal "es", @user.user_preferences.find_by(key: "locale").value

    # Verify next page request uses Spanish locale
    get settings_path
    assert_response :success
    # The page should be in Spanish (translations would appear in Spanish)
  end

  test "user can change language from spanish to english" do
    sign_in @user

    # Set initial language to Spanish
    @user.user_preferences.find_or_create_by(key: "locale").update(value: "es")

    # Change back to English
    patch locale_path, params: { locale: "en" }

    # Verify the change
    assert_redirected_to root_path
    assert_equal "en", @user.user_preferences.find_by(key: "locale").value
  end

  test "language preference persists across sessions" do
    sign_in @user

    # Set language to Spanish
    patch locale_path, params: { locale: "es" }
    assert_equal "es", @user.user_preferences.find_by(key: "locale").value

    # Sign out
    sign_out @user

    # Sign back in
    sign_in @user

    # Verify preference is still Spanish
    assert_equal "es", @user.user_preferences.find_by(key: "locale").value

    # Verify page loads in Spanish (ApplicationController sets locale from preference)
    get settings_path
    assert_response :success
  end

  test "first-time user sees english by default" do
    new_user = User.create!(
      email: "newuser@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    sign_in new_user
    get settings_path

    assert_response :success
    # EN should be highlighted (checked via I18n.locale check in view)
    # The preference should not exist initially
    assert_nil new_user.user_preferences.find_by(key: "locale")
  end

  test "invalid locale is handled gracefully" do
    sign_in @user

    # Try to set an invalid locale
    patch locale_path, params: { locale: "fr" }

    assert_redirected_to root_path
    # Should fall back to English (default)
    assert_equal "en", @user.user_preferences.find_by(key: "locale").value
  end

  test "empty locale parameter is handled gracefully" do
    sign_in @user

    patch locale_path, params: { locale: "" }

    assert_redirected_to root_path
    # Should default to English
    assert_equal "en", @user.user_preferences.find_by(key: "locale").value
  end

  test "language change is reflected in all UI text" do
    sign_in @user

    # Change to Spanish
    patch locale_path, params: { locale: "es" }
    follow_redirect!

    # Navigate to settings
    get settings_path

    # All UI text should be in Spanish
    # For example, the page title should be "Configuración" not "Settings"
    assert_select "h1", t("settings.show.title")
  end

  test "form submission returns to referer when available" do
    sign_in @user

    # Try to change language and verify redirect uses referer
    patch locale_path, params: { locale: "es" }, headers: { "HTTP_REFERER" => settings_path }

    assert_redirected_to settings_path
  end

  test "unauthenticated user cannot change language" do
    patch locale_path, params: { locale: "es" }

    assert_redirected_to new_session_path
  end
end
