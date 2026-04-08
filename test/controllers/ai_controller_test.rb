# frozen_string_literal: true

require "test_helper"

class AiControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "password", password_confirmation: "password")
    sign_in_as(@user)
  end

  # --- /ai/chat ---

  test "chat returns 401 redirect when not authenticated" do
    delete logout_path
    post ai_chat_path, params: { message: "hello" }, as: :json
    assert_response :redirect
  end

  test "chat returns no_api_key error when user has no Gemini key" do
    @user.update!(gemini_api_key: nil)
    post ai_chat_path, params: { message: "Analyze my portfolio" }, as: :json
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "no_api_key", json["error"]
  end

  test "chat returns AI response on success" do
    @user.update!(gemini_api_key: "AIzaFakeKey12345678")
    Ai::PortfolioContextBuilder.stub(:new, ->(_opts) {
      ctx = Object.new
      ctx.define_singleton_method(:call) { "Portfolio context here" }
      ctx
    }) do
      Ai::GeminiService.stub(:new, ->(_opts) {
        svc = Object.new
        svc.define_singleton_method(:generate) { |_opts| "Great portfolio!" }
        svc
      }) do
        post ai_chat_path, params: { message: "Analyze my portfolio" }, as: :json
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal "Great portfolio!", json["response"]
      end
    end
  end

  test "chat returns rate_limited error on Ai::RateLimitError" do
    @user.update!(gemini_api_key: "AIzaFakeKey12345678")
    Ai::PortfolioContextBuilder.stub(:new, ->(_opts) {
      ctx = Object.new; ctx.define_singleton_method(:call) { "" }; ctx
    }) do
      Ai::GeminiService.stub(:new, ->(_opts) {
        svc = Object.new
        svc.define_singleton_method(:generate) { |_opts| raise Ai::RateLimitError, "rate limited" }
        svc
      }) do
        post ai_chat_path, params: { message: "test" }, as: :json
        assert_response 429
        json = JSON.parse(response.body)
        assert_equal "rate_limited", json["error"]
      end
    end
  end

  test "chat returns invalid_key error on Ai::InvalidKeyError" do
    @user.update!(gemini_api_key: "AIzaBadKey")
    Ai::PortfolioContextBuilder.stub(:new, ->(_opts) {
      ctx = Object.new; ctx.define_singleton_method(:call) { "" }; ctx
    }) do
      Ai::GeminiService.stub(:new, ->(_opts) {
        svc = Object.new
        svc.define_singleton_method(:generate) { |_opts| raise Ai::InvalidKeyError, "bad key" }
        svc
      }) do
        post ai_chat_path, params: { message: "test" }, as: :json
        assert_response 401
        json = JSON.parse(response.body)
        assert_equal "invalid_key", json["error"]
      end
    end
  end

  # --- /ai/test_key ---

  test "test_key returns ok: true when key works" do
    Ai::GeminiService.stub(:new, ->(_opts) {
      svc = Object.new
      svc.define_singleton_method(:generate) { |_opts| "OK" }
      svc
    }) do
      post ai_test_key_path, params: { api_key: "AIzaGoodKey12345678" }, as: :json
      assert_response :success
      json = JSON.parse(response.body)
      assert_equal true, json["ok"]
    end
  end

  test "test_key returns invalid_key error when key is bad" do
    Ai::GeminiService.stub(:new, ->(_opts) {
      svc = Object.new
      svc.define_singleton_method(:generate) { |_opts| raise Ai::InvalidKeyError, "bad key" }
      svc
    }) do
      post ai_test_key_path, params: { api_key: "bad" }, as: :json
      assert_response 401
      json = JSON.parse(response.body)
      assert_equal "invalid_key", json["error"]
    end
  end

  # --- /ai/test_saved_key ---

  test "test_saved_key returns ok when stored key works" do
    @user.update!(gemini_api_key: "AIzaStoredKey12345678")
    Ai::GeminiService.stub(:new, ->(_opts) {
      svc = Object.new
      svc.define_singleton_method(:generate) { |_opts| "OK" }
      svc
    }) do
      post ai_test_saved_key_path, as: :json
      assert_response :success
      json = JSON.parse(response.body)
      assert_equal true, json["ok"]
    end
  end

  test "test_saved_key returns no_api_key when no key configured" do
    @user.update!(gemini_api_key: nil)
    post ai_test_saved_key_path, as: :json
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "no_api_key", json["error"]
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password" }
    follow_redirect!
  end
end
