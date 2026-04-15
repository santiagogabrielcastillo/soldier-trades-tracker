# frozen_string_literal: true

require "test_helper"

class Ai::ProviderForUserTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(gemini_api_key: nil)
  end

  # ── client resolution ──────────────────────────────────────────────────────

  test "returns ClaudeService when platform anthropic key is configured" do
    with_anthropic_key("sk-ant-platform-key") do
      client = Ai::ProviderForUser.new(@user).client
      assert_instance_of Ai::ClaudeService, client
    end
  end

  test "returns GeminiService when no anthropic key but gemini key is configured" do
    @user.update!(gemini_api_key: "AIzaGeminiKey")
    with_no_anthropic_key do
      client = Ai::ProviderForUser.new(@user).client
      assert_instance_of Ai::GeminiService, client
    end
  end

  test "returns nil when neither key is configured" do
    with_no_anthropic_key do
      client = Ai::ProviderForUser.new(@user).client
      assert_nil client
    end
  end

  test "prefers Claude over Gemini when both are available" do
    @user.update!(gemini_api_key: "AIzaGeminiKey")
    with_anthropic_key("sk-ant-platform-key") do
      client = Ai::ProviderForUser.new(@user).client
      assert_instance_of Ai::ClaudeService, client
    end
  end

  # ── predicates ────────────────────────────────────────────────────────────

  test "claude? is true when anthropic key is present" do
    with_anthropic_key("sk-ant-platform-key") do
      assert Ai::ProviderForUser.new(@user).claude?
    end
  end

  test "claude? is false when no anthropic key" do
    with_no_anthropic_key do
      refute Ai::ProviderForUser.new(@user).claude?
    end
  end

  test "gemini? is true when gemini key present and no anthropic key" do
    @user.update!(gemini_api_key: "AIzaGeminiKey")
    with_no_anthropic_key do
      assert Ai::ProviderForUser.new(@user).gemini?
    end
  end

  test "gemini? is false when anthropic key takes precedence" do
    @user.update!(gemini_api_key: "AIzaGeminiKey")
    with_anthropic_key("sk-ant-platform-key") do
      refute Ai::ProviderForUser.new(@user).gemini?
    end
  end

  test "configured? is true when claude available" do
    with_anthropic_key("sk-ant-platform-key") do
      assert Ai::ProviderForUser.new(@user).configured?
    end
  end

  test "configured? is true when gemini available" do
    @user.update!(gemini_api_key: "AIzaGeminiKey")
    with_no_anthropic_key do
      assert Ai::ProviderForUser.new(@user).configured?
    end
  end

  test "configured? is false when neither key present" do
    with_no_anthropic_key do
      refute Ai::ProviderForUser.new(@user).configured?
    end
  end

  private

  def with_anthropic_key(key)
    credentials_stub = { anthropic: { api_key: key } }
    Rails.application.credentials.stub(:dig, ->(section, field) {
      credentials_stub.dig(section, field)
    }) { yield }
  end

  def with_no_anthropic_key
    Rails.application.credentials.stub(:dig, ->(*_args) { nil }) { yield }
  end
end
