# frozen_string_literal: true

module Stocks
  # Generates AI investment analysis for a list of tickers.
  # Routes to Claude (deep analysis + web search) or Gemini (standard analysis)
  # based on Ai::ProviderForUser resolution.
  # Results are upserted into stock_analyses (one record per user+ticker).
  class SyncStockAnalysisJob < ApplicationJob
    queue_as :default

    GEMINI_RATE_LIMIT_DELAY = 1.0 # seconds between Gemini requests
    CLAUDE_RATE_LIMIT_DELAY = 3.0 # Claude + web search takes longer per ticker

    def perform(user_id, tickers)
      user     = User.find(user_id)
      provider = Ai::ProviderForUser.new(user)

      return unless provider.configured?

      client       = provider.client
      fundamentals = StockFundamental.for_tickers(tickers)
      delay        = provider.claude? ? CLAUDE_RATE_LIMIT_DELAY : GEMINI_RATE_LIMIT_DELAY
      now          = Time.current

      tickers.each_with_index do |ticker, i|
        sleep(delay) if i > 0

        begin
          raw    = generate(client, provider, ticker, fundamentals[ticker])
          parsed = extract_json(raw)
          attrs  = build_attrs(parsed, provider, user, ticker, now)

          StockAnalysis.upsert(
            attrs,
            unique_by: [ :user_id, :ticker ],
            update_only: %i[
              rating executive_summary risk_reward_rating thesis_breakdown
              red_flags structured_data provider analyzed_at
            ]
          )

          Rails.logger.info("[Stocks::SyncStockAnalysisJob] #{ticker}: #{attrs[:rating]} via #{attrs[:provider]}")
        rescue Ai::Error => e
          Rails.logger.error("[Stocks::SyncStockAnalysisJob] #{ticker} AI error: #{e.message}")
        rescue JSON::ParserError => e
          Rails.logger.error("[Stocks::SyncStockAnalysisJob] #{ticker} JSON parse error: #{e.message}")
        end
      end

      Rails.logger.info("[Stocks::SyncStockAnalysisJob] Completed #{tickers.size} tickers for user #{user_id}")
    end

    private

    def generate(client, provider, ticker, fundamental)
      if provider.claude?
        builder = Stocks::DeepAnalysisPromptBuilder.new(ticker: ticker, fundamental: fundamental)
        client.generate(
          prompt: builder.prompt,
          system: builder.system_prompt,
          tools:  builder.tools
        )
      else
        prompt = Stocks::AnalysisPromptBuilder.call(ticker: ticker, fundamental: fundamental)
        client.generate(prompt: prompt)
      end
    end

    # Strips markdown fences if Claude wraps output despite instructions, then parses JSON.
    def extract_json(raw)
      cleaned = raw.to_s.strip.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "")
      JSON.parse(cleaned)
    end

    def build_attrs(parsed, provider, user, ticker, now)
      if provider.claude?
        build_claude_attrs(parsed, user, ticker, now)
      else
        build_gemini_attrs(parsed, user, ticker, now)
      end
    end

    def build_claude_attrs(parsed, user, ticker, now)
      {
        user_id:            user.id,
        ticker:             ticker,
        rating:             normalize_rating(parsed["verdict"]),
        executive_summary:  parsed["executive_summary"],
        risk_reward_rating: parsed["risk_reward_rating"],
        thesis_breakdown:   parsed["thesis_breakdown"],
        red_flags:          parsed["red_flags"],
        structured_data:    parsed,
        provider:           "claude",
        analyzed_at:        now,
        created_at:         now,
        updated_at:         now
      }
    end

    def build_gemini_attrs(parsed, user, ticker, now)
      {
        user_id:            user.id,
        ticker:             ticker,
        rating:             normalize_rating(parsed["rating"]),
        executive_summary:  parsed["executive_summary"],
        risk_reward_rating: parsed["risk_reward_rating"],
        thesis_breakdown:   parsed["thesis_breakdown"],
        red_flags:          parsed["red_flags"],
        structured_data:    nil,
        provider:           "gemini",
        analyzed_at:        now,
        created_at:         now,
        updated_at:         now
      }
    end

    VALID_RATINGS = %w[buy accumulate watch hold sell].freeze

    def normalize_rating(value)
      rating = value.to_s.downcase.strip
      VALID_RATINGS.include?(rating) ? rating : "watch"
    end
  end
end
