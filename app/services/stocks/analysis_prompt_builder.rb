# frozen_string_literal: true

module Stocks
  # Builds a Gemini prompt for value investment analysis of a single ticker.
  # Embeds available fundamentals and the value investment thesis framework.
  # Returns a prompt string that instructs Gemini to respond with JSON only.
  class AnalysisPromptBuilder
    def self.call(ticker:, fundamental:)
      new(ticker, fundamental).call
    end

    def initialize(ticker, fundamental)
      @ticker      = ticker
      @fundamental = fundamental
    end

    def call
      <<~PROMPT
        You are a Senior Value Investment Analyst specializing in Fundamental Analysis and Portfolio Management. Your objective is to evaluate companies using a strict "Owner Mentality" framework.

        Analyze **#{@ticker}** based on the following data and framework:

        ## Available Fundamentals
        - Sector: #{field(:sector)}
        - Industry: #{field(:industry)}
        - P/E: #{field(:pe)}
        - Forward P/E: #{field(:fwd_pe)}
        - PEG: #{field(:peg)}
        - P/S: #{field(:ps)}
        - P/FCF: #{field(:pfcf)}
        - EV/EBITDA: #{field(:ev_ebitda)}
        - Net Margin: #{pct_field(:net_margin)}
        - ROE: #{pct_field(:roe)}
        - ROIC: #{pct_field(:roic)}
        - Debt/Equity: #{field(:debt_eq)}
        - Sales Y/Y: #{pct_field(:sales_5y)}
        - Sales Q/Q: #{pct_field(:sales_qq)}

        ## Investment Framework

        1. **Business Model & Moat Analysis:**
           - Identify the core business model.
           - Classify as Asset Light (tech, software, intangible-based) or Asset Heavy (manufacturing, energy, intensive CapEx).
           - Evaluate the Economic Moat (Scale, Switching Costs, Network Effect, or Intangibles). If no moat is identified, apply a higher margin of safety.

        2. **Quantitative Health & Solvency (Mandatory):**
           - Debt/Equity < 0.5 is excellent; > 1.0 is a warning sign; > 2.0 indicates high leverage risk (use as proxy for Net Debt/EBITDA when EV/EBITDA is unavailable).
           - Analyze Revenue vs. Earnings: Prioritize revenue stability. If earnings are down due to reinvestment but revenue remains strong, maintain a neutral-to-positive outlook.
           - EV/EBITDA < 15 is reasonable; > 30 warrants scrutiny.

        3. **Valuation & Sentiment:**
           - Analyze P/E in context of asset intensity (higher P/E is acceptable for Asset Light; lower P/E is expected for Asset Heavy).
           - Value Trap Check: If P/E is significantly below industry average, identify the market's reason. Do not assume it is "cheap" without identifying a specific market sentiment bias.
           - Determine Margin of Safety required based on systemic risk and liquidity.

        4. **Portfolio Fit:**
           - Assess potential Sharpe Ratio contribution.
           - Distinguish between growth drivers (Appreciation) and income drivers (Dividends).

        ## Required Output

        Respond with ONLY a JSON object — no markdown fences, no explanation, no text outside the JSON:

        {"rating":"buy","executive_summary":"1-2 sentence verdict.","risk_reward_rating":"Excellent/Good/Fair/Poor — one sentence with key leverage and risk insight.","thesis_breakdown":"3-5 sentence qualitative moat and quantitative valuation analysis.","red_flags":"Comma-separated red flags, or None if clean."}

        Use one of these exact values for rating: buy, hold, sell, watch.
      PROMPT
    end

    private

    def field(attr)
      return "N/A" if @fundamental.nil?
      val = @fundamental.public_send(attr)
      val.present? ? val.to_s : "N/A"
    end

    def pct_field(attr)
      return "N/A" if @fundamental.nil?
      val = @fundamental.public_send(attr)
      val.present? ? "#{val}%" : "N/A"
    end
  end
end
