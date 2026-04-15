# frozen_string_literal: true

module Ai
  # Returns the appropriate AI client for a user.
  #
  # Resolution order:
  #   1. Platform Anthropic key in credentials → ClaudeService (deep analysis, web search)
  #   2. User's own Gemini key → GeminiService (standard analysis)
  #   3. Neither configured → nil
  #
  # Usage:
  #   provider = Ai::ProviderForUser.new(user)
  #   provider.client     # → Ai::ClaudeService | Ai::GeminiService | nil
  #   provider.claude?    # → true if Claude will be used
  class ProviderForUser
    def initialize(user)
      @user = user
    end

    def client
      if anthropic_api_key.present?
        Ai::ClaudeService.new(api_key: anthropic_api_key)
      elsif @user.gemini_api_key.present?
        Ai::GeminiService.new(api_key: @user.gemini_api_key)
      end
    end

    def claude?
      anthropic_api_key.present?
    end

    def gemini?
      !claude? && @user.gemini_api_key.present?
    end

    def configured?
      claude? || gemini?
    end

    private

    def anthropic_api_key
      @anthropic_api_key ||= Rails.application.credentials.dig(:anthropic, :api_key).presence
    end
  end
end
