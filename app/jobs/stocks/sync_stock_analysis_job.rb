# frozen_string_literal: true

module Stocks
  # Generates AI investment analysis for a list of tickers using the user's Gemini key.
  # Results are upserted into stock_analyses (one record per user+ticker).
  # Skips silently if the user has no Gemini key configured.
  class SyncStockAnalysisJob < ApplicationJob
    queue_as :default

    RATE_LIMIT_DELAY = 1.0 # seconds between Gemini requests

    def perform(user_id, tickers)
      user = User.find(user_id)
      return unless user.gemini_api_key_configured?

      gemini       = Ai::GeminiService.new(api_key: user.gemini_api_key)
      fundamentals = StockFundamental.for_tickers(tickers)
      now          = Time.current

      tickers.each_with_index do |ticker, i|
        sleep(RATE_LIMIT_DELAY) if i > 0

        prompt = Stocks::AnalysisPromptBuilder.call(
          ticker:      ticker,
          fundamental: fundamentals[ticker]
        )

        begin
          raw    = gemini.generate(prompt: prompt)
          parsed = JSON.parse(raw)

          StockAnalysis.upsert(
            {
              user_id:            user.id,
              ticker:             ticker,
              rating:             parsed["rating"].to_s.downcase.presence || "watch",
              executive_summary:  parsed["executive_summary"],
              risk_reward_rating: parsed["risk_reward_rating"],
              thesis_breakdown:   parsed["thesis_breakdown"],
              red_flags:          parsed["red_flags"],
              analyzed_at:        now,
              created_at:         now,
              updated_at:         now
            },
            unique_by: [ :user_id, :ticker ],
            update_only: %i[rating executive_summary risk_reward_rating thesis_breakdown red_flags analyzed_at]
          )

          Rails.logger.info("[Stocks::SyncStockAnalysisJob] #{ticker}: #{parsed['rating']}")
        rescue Ai::Error => e
          Rails.logger.error("[Stocks::SyncStockAnalysisJob] #{ticker} Gemini error: #{e.message}")
        rescue JSON::ParserError => e
          Rails.logger.error("[Stocks::SyncStockAnalysisJob] #{ticker} JSON parse error: #{e.message}")
        end
      end

      Rails.logger.info("[Stocks::SyncStockAnalysisJob] Completed #{tickers.size} tickers for user #{user_id}")
    end
  end
end
