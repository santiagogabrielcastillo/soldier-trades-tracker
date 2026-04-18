# frozen_string_literal: true

require "test_helper"

module Ai
  class ProviderForUserTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
    end

    test "uses user anthropic key when configured" do
      @user.user_api_keys.create!(provider: "anthropic", key: "sk-ant-test")
      provider = ProviderForUser.new(@user)
      assert provider.claude?
      assert_not provider.gemini?
      assert provider.configured?
    end

    test "falls back to gemini key when no anthropic key" do
      @user.user_api_keys.create!(provider: "gemini", key: "AIza-test")
      provider = ProviderForUser.new(@user)
      assert_not provider.claude?
      assert provider.gemini?
      assert provider.configured?
    end

    test "not configured when neither key present" do
      provider = ProviderForUser.new(@user)
      assert_not provider.configured?
      assert_nil provider.client
    end

    test "anthropic takes priority over gemini" do
      @user.user_api_keys.create!(provider: "anthropic", key: "sk-ant-test")
      @user.user_api_keys.create!(provider: "gemini", key: "AIza-test")
      provider = ProviderForUser.new(@user)
      assert provider.claude?
      assert_not provider.gemini?
    end
  end
end
