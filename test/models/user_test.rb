# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "admin defaults to false" do
    user = User.new(email: "test@example.com", password: "password")
    assert_equal false, user.admin
  end

  test "gemini_api_key_configured? returns false when key is nil" do
    user = User.new(email: "ai@example.com", password: "password")
    assert_equal false, user.gemini_api_key_configured?
  end

  test "gemini_api_key_configured? returns true when key is set" do
    user = users(:one)
    user.gemini_api_key = "AIzaSyTestKey12345678"
    assert_equal true, user.gemini_api_key_configured?
  end

  test "gemini_api_key_masked returns nil when key is blank" do
    user = User.new(email: "ai@example.com", password: "password")
    assert_nil user.gemini_api_key_masked
  end

  test "gemini_api_key_masked returns masked string when key is set" do
    user = users(:one)
    user.gemini_api_key = "AIzaSyTestKey12345678"
    assert_equal "AIza...5678", user.gemini_api_key_masked
  end
end
