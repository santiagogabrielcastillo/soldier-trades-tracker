# frozen_string_literal: true

module Ai
  # Returns the appropriate AI client for a user based on their stored BYOK keys.
  #
  # Resolution order:
  #   1. User's own Anthropic key → ClaudeService (deep analysis, web search)
  #   2. User's own Gemini key → GeminiService (standard analysis)
  #   3. Neither configured → nil
  class ProviderForUser
    def initialize(user)
      @user = user
    end

    def client
      if anthropic_api_key.present?
        Ai::ClaudeService.new(api_key: anthropic_api_key)
      elsif gemini_api_key.present?
        Ai::GeminiService.new(api_key: gemini_api_key)
      end
    end

    def claude?
      anthropic_api_key.present?
    end

    def gemini?
      !claude? && gemini_api_key.present?
    end

    def configured?
      claude? || gemini?
    end

    private

    def anthropic_api_key
      @anthropic_api_key ||= UserApiKey.key_for(@user, :anthropic)
    end

    def gemini_api_key
      @gemini_api_key ||= UserApiKey.key_for(@user, :gemini)
    end
  end
end
