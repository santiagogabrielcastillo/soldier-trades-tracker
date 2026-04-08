# frozen_string_literal: true

class AiController < ApplicationController
  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a portfolio analysis assistant for a complete investment tracker.
    You have access to the user's crypto futures trading positions, spot holdings,
    stock portfolio, asset allocation, and watchlist with fundamentals.
    Provide insights about trading performance, diversification, sector and asset exposure,
    risk, and watchlist valuations when asked.
    You are NOT a financial advisor — always remind users to do their own research.
    Never give specific buy/sell recommendations.
    Be concise and data-driven in your analysis.
  PROMPT

  def chat
    unless current_user.gemini_api_key_configured?
      return render json: {
        error: "no_api_key",
        message: "Please add your Gemini API key in Settings to use the AI assistant."
      }, status: :unprocessable_entity
    end

    message = params[:message].to_s.strip
    return render json: { error: "empty_message", message: "Message cannot be blank." }, status: :unprocessable_entity if message.blank?

    context = Ai::PortfolioContextBuilder.new(user: current_user).call
    prompt = "#{SYSTEM_PROMPT}Today's date: #{Date.today}.\n\n#{context}\n\nUser question: #{message}"

    response_text = Ai::GeminiService.new(api_key: current_user.gemini_api_key).generate(prompt: prompt)
    render json: { response: response_text }
  rescue Ai::RateLimitError
    render json: {
      error: "rate_limited",
      message: "You've hit your free tier limit. Try again in a moment."
    }, status: 429
  rescue Ai::InvalidKeyError
    render json: {
      error: "invalid_key",
      message: "Your API key appears to be invalid. Please check it in Settings."
    }, status: :unauthorized
  rescue Ai::ServiceError
    render json: {
      error: "service_error",
      message: "The AI service is temporarily unavailable."
    }, status: :unprocessable_entity
  end

  def test_key
    api_key = params[:api_key].to_s.strip
    return render json: { error: "no_api_key", message: "API key cannot be blank." }, status: :unprocessable_entity if api_key.blank?

    Ai::GeminiService.new(api_key: api_key).generate(prompt: "Say OK")
    render json: { ok: true }
  rescue Ai::RateLimitError
    render json: { error: "rate_limited", message: "Rate limited. Try again in a moment." }, status: 429
  rescue Ai::InvalidKeyError
    render json: { error: "invalid_key", message: "Your API key appears to be invalid." }, status: :unauthorized
  rescue Ai::ServiceError
    render json: { error: "service_error", message: "Could not reach the AI service." }, status: :unprocessable_entity
  end

  def test_saved_key
    unless current_user.gemini_api_key_configured?
      return render json: { error: "no_api_key", message: "No key configured." }, status: :unprocessable_entity
    end

    Ai::GeminiService.new(api_key: current_user.gemini_api_key).generate(prompt: "Say OK")
    render json: { ok: true }
  rescue Ai::RateLimitError
    render json: { error: "rate_limited", message: "Rate limited. Try again in a moment." }, status: 429
  rescue Ai::InvalidKeyError
    render json: { error: "invalid_key", message: "Your API key appears to be invalid." }, status: :unauthorized
  rescue Ai::ServiceError
    render json: { error: "service_error", message: "Could not reach the AI service." }, status: :unprocessable_entity
  end
end
