# frozen_string_literal: true

module Stocks
  # Builds the prompt for Claude-powered deep stock analysis with web search.
  #
  # Phase 1 (research) is handled autonomously by Claude's web search tool.
  # This builder provides Phase 2 (framework) + fundamentals + JSON schema.
  #
  # Usage:
  #   builder = Stocks::DeepAnalysisPromptBuilder.new(ticker: "AAPL", fundamental: stock_fundamental)
  #   client.generate(prompt: builder.prompt, system: builder.system_prompt, tools: builder.tools)
  class DeepAnalysisPromptBuilder
    SYSTEM_PROMPT = <<~SYSTEM
      You are a Senior Value Investment Analyst. Your job is to research a company using web search,
      apply a rigorous owner-mentality investment framework, and return a structured JSON analysis.

      ## Phase 2: Analysis Framework

      Apply this framework after gathering data via web search. Work through each section methodically.

      ### Business Model & Moat

      Classify asset intensity:
      - Asset Light: software, SaaS, platforms, IP/brand-driven, services. CapEx/Revenue < 10%.
        Acceptable P/E: up to 30–40x if growth > 15% and margins expanding.
      - Asset Heavy: manufacturing, energy, infrastructure, telecom. CapEx/Revenue > 15%.
        P/E above 20x needs strong justification; above 25x is a yellow flag.

      Score economic moat on each dimension (0–5):
      - Switching costs: renewal rates, contract lengths, integration depth, replacement cost
      - Scale advantage: market share, cost structure, distribution reach
      - Network effect: does each additional user/node make the product more valuable?
      - Intangibles: patents, brands, regulatory licenses, proprietary data

      If no moat dimension scores above 2, flag this. The primary moat threat must be concrete —
      "AI disruption" is too vague; "AI agents reducing per-seat license demand by automating
      Tier-1 support tickets" is useful.

      ### Solvency Check

      Net Debt / EBITDA = (Total Debt − Cash − Short-term Investments) / TTM EBITDA:
      - Negative (net cash): Excellent
      - < 1.5x: Excellent
      - 1.5x–2.0x: Acceptable — monitor trajectory
      - 2.0x–3.0x: Warning — needs justification
      - > 3.0x: Red flag — solvency risk

      Sector-specific: For insurance/managed care, supplement with MCR, interest coverage,
      debt-to-capital. For banks, use CET1, tangible book value, NIM instead. For REITs,
      use FFO, AFFO, debt/gross assets instead.

      ### Valuation & Value Trap Check

      If P/E is significantly below the company's own 5-year history or industry average,
      do NOT call it "cheap." Instead, identify the market's specific reason for the discount,
      then assess whether that fear reflects actual deterioration or anticipated future deterioration.

      Turnaround classification (when a crisis is detected):
      - Reversible operational stress: revenue stable, franchise intact, new leadership has plan
      - Structural franchise damage: permanently impaired competitive position, declining revenue
      - Unresolvable legal uncertainty: outcome range so wide intrinsic value can't be estimated

      Margin of safety required:
      - Standard: 15–20%
      - High uncertainty: 25%+
      - No moat: 30%+
      - Speculative/pre-revenue: 40%+

      ### Output Rules

      - Every claim must trace to a specific data point from web search or provided fundamentals
      - Show calculations explicitly (Net Debt / EBITDA = X / Y = Z)
      - Flag anything unverified
      - Turnaround mode: set turnaround_mode true and classify into one of three buckets
      - Include URLs of key sources in the sources array
      - Return ONLY a JSON object — no markdown fences, no explanation, no text outside the JSON
    SYSTEM

    SECTOR_NOTES = {
      "Financial" => <<~NOTES,
        ## Sector Note: Financials (Banks, Insurance, Asset Managers)
        Net Debt/EBITDA is not meaningful — banks' "debt" is their raw material (deposits).
        For banks: use CET1 ratio (>10% strong), tangible book value per share, NIM, efficiency ratio (<55% = well-run), ROTCE (>15% exceptional).
        For insurance/managed care: MCR (below 83% strong, above 86% compression), operating margin 4–9% is normal,
        cash from ops / net income should be >1.2x, interest coverage >4x, debt-to-capital <50%.
        For P&C: combined ratio (below 100% = underwriting profit).
        Valuation: P/E of 12–22x typical for large managed care. EV/Revenue is less useful.
      NOTES

      "Healthcare" => <<~NOTES,
        ## Sector Note: Healthcare (Pharma, Biotech, Medtech)
        For large pharma: analyze patent cliff (when do key drugs lose exclusivity?).
        For pre-revenue biotech: standard P/E and EBITDA frameworks don't apply — focus on cash runway,
        pipeline probability-adjusted NPV, binary catalysts. Apply 40%+ margin of safety.
        For medtech: razor/blade model (low-margin device + high-margin consumables), regulatory approval as moat.
      NOTES

      "Energy" => <<~NOTES,
        ## Sector Note: Energy (Oil & Gas, Utilities, Renewables)
        Normalize earnings across the full cycle (5–7 year average). Never value on peak-cycle earnings.
        Use Debt/EBITDAX for E&P. Track breakeven price, reserve replacement ratio, F&D costs.
        For utilities: regulated vs. unregulated revenue mix, rate case outcomes, allowed ROE.
      NOTES

      "Real Estate" => <<~NOTES,
        ## Sector Note: REITs
        Replace P/E with P/FFO. Use AFFO (FFO minus maintenance CapEx) as sustainable cash flow proxy.
        Dividend payout <85% of AFFO = sustainable. Occupancy >90% expected. Debt/Gross Assets <40% conservative, >50% aggressive.
        Same-store NOI growth is the organic growth indicator.
      NOTES

      "Technology" => <<~NOTES,
        ## Sector Note: Technology (SaaS, Platforms, Hardware)
        For SaaS: ARR/MRR, net revenue retention (>110% strong, >130% exceptional), Rule of 40,
        gross margin (>75% expected), SBC as % of revenue (>20% = dilution flag).
        For semiconductors: normalize across inventory cycle, track design wins, inventory days.
        Developer ecosystem lock-in and data network effects are primary moat indicators.
      NOTES

      "Consumer Staples" => <<~NOTES,
        ## Sector Note: Consumer Staples & Retail
        Same-store sales growth is the most important organic metric. Track inventory turnover,
        gross margin stability (evidenced pricing power despite input cost inflation),
        private label penetration risk.
      NOTES

      "Consumer Cyclical" => <<~NOTES
        ## Sector Note: Consumer Cyclical & Retail
        Same-store sales growth is the most important organic metric. Track inventory turnover,
        gross margin stability, and private label penetration risk. Normalize across the consumer cycle.
      NOTES
    }.freeze

    JSON_SCHEMA = <<~SCHEMA
      Return ONLY this JSON object with no other text:

      {
        "verdict": "buy|accumulate|watch|hold|sell",
        "verdict_label": "Buy — strong fundamentals at cyclical low",
        "company_name": "Full company name",
        "analyzed_at": "YYYY-MM-DD",

        "metrics": {
          "price":           { "value": "$X", "subtitle": "YTD or vs 52w high context" },
          "market_cap":      { "value": "$XB", "subtitle": "shares outstanding" },
          "forward_pe":      { "value": "Xx", "subtitle": "vs 5y avg ~Xx" },
          "ev_revenue":      { "value": "~Xx", "subtitle": "vs historical median" },
          "net_debt_ebitda": { "value": "Xx or Net cash", "subtitle": "debt vs cash detail", "status": "excellent|acceptable|warning|red_flag" },
          "fcf_margin":      { "value": "X%", "subtitle": "$XB FCF" },
          "renewal_or_retention": { "value": "X%", "subtitle": "context (e.g. multi-year streak)" },
          "revenue_growth":  { "value": "X%", "subtitle": "FY period YoY" }
        },

        "moat": {
          "overall": "wide|narrow|none",
          "scores": {
            "switching_costs": { "score": 0, "max": 5 },
            "scale_advantage": { "score": 0, "max": 5 },
            "network_effect":  { "score": 0, "max": 5 },
            "intangibles":     { "score": 0, "max": 5 }
          },
          "primary_threat": "Specific concrete threat description"
        },

        "revenue_trend": [
          { "year": "FY21", "revenue": 0.0, "fcf": 0.0 }
        ],
        "revenue_unit": "B or M",

        "tags": [
          { "label": "tag text", "color": "green|amber|red" }
        ],

        "asset_classification": "light|heavy|hybrid",
        "turnaround_mode": false,
        "turnaround_bucket": null,

        "executive_summary": "3-5 sentence analysis covering what the company does, core thesis, valuation context, and verdict.",
        "thesis_breakdown": "Detailed qualitative and quantitative analysis. Show calculations. Reference specific products, customers, deals.",
        "risk_reward_rating": "Excellent|Good|Fair|Poor — one sentence with key leverage and risk insight.",
        "red_flags": "Numbered red flags, each 2-3 sentences. Quantify where possible. Minimum 3 flags.",
        "what_to_watch": "3-5 upcoming catalysts and events with dates where known.",
        "sources": ["url1", "url2"]
      }

      Rules for specific fields:
      - verdict: exactly one of buy, accumulate, watch, hold, sell
      - turnaround_bucket: null OR exactly one of "reversible_operational_stress", "structural_franchise_damage", "unresolvable_legal_uncertainty"
      - revenue_trend: 5 years of data if available, most recent last. Use null for missing FCF values.
      - tags: 4-7 tags total. green = strength, amber = mixed/watch, red = risk
      - net_debt_ebitda status: excellent (<1.5x or net cash), acceptable (1.5-2x), warning (2-3x), red_flag (>3x)
      - renewal_or_retention: use net revenue retention for SaaS, renewal rate for subscription, customer retention for others
    SCHEMA

    def self.call(ticker:, fundamental:)
      new(ticker: ticker, fundamental: fundamental).prompt
    end

    def initialize(ticker:, fundamental:)
      @ticker      = ticker
      @fundamental = fundamental
    end

    def prompt
      <<~PROMPT
        Analyze **#{@ticker}** using the owner-mentality value investment framework.

        ## Step 1: Web Research

        Use the web_search tool to gather current data. Run searches for:
        1. Current stock price, 52-week range, market cap, YTD performance
        2. Most recent earnings results (beat/miss vs consensus, guidance)
        3. 5-year revenue and free cash flow history
        4. Net debt, cash, EBITDA for the solvency check
        5. Forward P/E, EV/Revenue, EV/EBITDA vs historical averages
        6. Analyst ratings and recent upgrades/downgrades
        7. Crisis scan: "#{@ticker} investigation lawsuit CEO resignation controversy #{Time.current.year}"
        8. If crisis found: gather details on scope, new leadership, guidance status

        ## Step 2: Available Fundamentals (from Finviz)

        Use these as a starting point — verify and supplement with web search:
        #{fundamentals_block}

        #{sector_notes}
        ## Step 3: Output

        #{JSON_SCHEMA}
      PROMPT
    end

    def system_prompt
      SYSTEM_PROMPT
    end

    def tools
      [ Ai::ClaudeService::WEB_SEARCH_TOOL ]
    end

    private

    def fundamentals_block
      if @fundamental.nil?
        "No fundamentals available — rely entirely on web search."
      else
        <<~BLOCK
          - Sector: #{field(:sector)}
          - Industry: #{field(:industry)}
          - P/E (trailing): #{field(:pe)}
          - Forward P/E: #{field(:fwd_pe)}
          - PEG: #{field(:peg)}
          - P/S: #{field(:ps)}
          - P/FCF: #{field(:pfcf)}
          - EV/EBITDA: #{field(:ev_ebitda)}
          - Net Margin: #{pct_field(:net_margin)}
          - ROE: #{pct_field(:roe)}
          - ROIC: #{pct_field(:roic)}
          - Debt/Equity: #{field(:debt_eq)}
          - Revenue Growth (5Y avg): #{pct_field(:sales_5y)}
          - Revenue Growth (Q/Q): #{pct_field(:sales_qq)}
        BLOCK
      end
    end

    def sector_notes
      return "" if @fundamental.nil?
      sector = @fundamental.sector.to_s

      note = SECTOR_NOTES[sector]
      return "" unless note.present?

      "#{note}\n"
    end

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
