# frozen_string_literal: true

require "test_helper"

class LocaleControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:santiago)
    sign_in @user
  end

  test "update locale to spanish" do
    patch locale_path, params: { locale: "es" }

    assert_redirected_to root_path
    assert_equal I18n.t("flash.language_changed"), flash[:notice]
    assert_equal "es", @user.user_preferences.find_by(key: "locale").value
  end

  test "update locale to english" do
    # First set to Spanish
    @user.user_preferences.find_or_create_by(key: "locale").update(value: "es")

    # Then change back to English
    patch locale_path, params: { locale: "en" }

    assert_redirected_to root_path
    assert_equal I18n.t("flash.language_changed"), flash[:notice]
    assert_equal "en", @user.user_preferences.find_by(key: "locale").value
  end

  test "invalid locale falls back to default" do
    patch locale_path, params: { locale: "fr" }

    assert_redirected_to root_path
    assert_equal I18n.t("flash.language_changed"), flash[:notice]
    # Should fall back to default locale (en)
    assert_equal "en", @user.user_preferences.find_by(key: "locale").value
  end

  test "update creates preference if not exists" do
    assert_nil @user.user_preferences.find_by(key: "locale")

    patch locale_path, params: { locale: "es" }

    assert_equal "es", @user.user_preferences.find_by(key: "locale").value
  end

  test "unauthenticated user is redirected" do
    sign_out @user

    patch locale_path, params: { locale: "es" }

    assert_redirected_to new_session_path
  end

  test "redirect uses referer when available" do
    settings_page = settings_path
    patch locale_path, params: { locale: "es" }, headers: { "HTTP_REFERER" => settings_page }

    assert_redirected_to settings_page
  end

  test "redirect uses fallback when no referer" do
    patch locale_path, params: { locale: "es" }

    assert_redirected_to root_path
  end
end
