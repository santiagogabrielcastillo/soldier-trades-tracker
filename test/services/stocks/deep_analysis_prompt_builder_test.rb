# frozen_string_literal: true

require "test_helper"

module Stocks
  class DeepAnalysisPromptBuilderTest < ActiveSupport::TestCase
    def build_fundamental(overrides = {})
      StockFundamental.new(
        ticker:     overrides.fetch(:ticker,     "AAPL"),
        pe:         overrides.fetch(:pe,         BigDecimal("28.5")),
        fwd_pe:     overrides.fetch(:fwd_pe,     BigDecimal("25.1")),
        peg:        overrides.fetch(:peg,         BigDecimal("2.3")),
        ps:         overrides.fetch(:ps,          BigDecimal("7.5")),
        pfcf:       overrides.fetch(:pfcf,        BigDecimal("30.2")),
        ev_ebitda:  overrides.fetch(:ev_ebitda,   BigDecimal("22.1")),
        net_margin: overrides.fetch(:net_margin,  BigDecimal("25.31")),
        roe:        overrides.fetch(:roe,         BigDecimal("147.25")),
        roic:       overrides.fetch(:roic,        BigDecimal("55.1")),
        debt_eq:    overrides.fetch(:debt_eq,     BigDecimal("1.87")),
        sales_5y:   overrides.fetch(:sales_5y,    BigDecimal("2.02")),
        sales_qq:   overrides.fetch(:sales_qq,    BigDecimal("4.87")),
        sector:     overrides.fetch(:sector,      "Technology"),
        industry:   overrides.fetch(:industry,    "Consumer Electronics"),
        fetched_at: Time.current
      )
    end

    # ── prompt content ────────────────────────────────────────────────────────

    test "prompt includes ticker" do
      builder = Stocks::DeepAnalysisPromptBuilder.new(ticker: "AAPL", fundamental: build_fundamental)
      assert_includes builder.prompt, "AAPL"
    end

    test "prompt includes fundamental metrics" do
      f = build_fundamental(pe: BigDecimal("28.5"), roe: BigDecimal("147.25"))
      prompt = Stocks::DeepAnalysisPromptBuilder.new(ticker: "AAPL", fundamental: f).prompt
      assert_includes prompt, "28.5"
      assert_includes prompt, "147.25"
    end

    test "prompt includes sector and industry" do
      f = build_fundamental(sector: "Technology", industry: "Consumer Electronics")
      prompt = Stocks::DeepAnalysisPromptBuilder.new(ticker: "AAPL", fundamental: f).prompt
      assert_includes prompt, "Technology"
      assert_includes prompt, "Consumer Electronics"
    end

    test "prompt instructs web search for current data" do
      prompt = Stocks::DeepAnalysisPromptBuilder.new(ticker: "AAPL", fundamental: build_fundamental).prompt
      assert_includes prompt, "web_search"
      assert_includes prompt, "current"
    end

    test "prompt requests JSON output with required fields" do
      prompt = Stocks::DeepAnalysisPromptBuilder.new(ticker: "AAPL", fundamental: build_fundamental).prompt
      assert_includes prompt, '"verdict"'
      assert_includes prompt, '"executive_summary"'
      assert_includes prompt, '"moat"'
      assert_includes prompt, '"revenue_trend"'
      assert_includes prompt, '"tags"'
      assert_includes prompt, '"red_flags"'
    end

    test "prompt handles nil individual fundamental fields gracefully" do
      f = build_fundamental(pe: nil, sector: nil, ev_ebitda: nil)
      prompt = Stocks::DeepAnalysisPromptBuilder.new(ticker: "AAPL", fundamental: f).prompt
      assert_includes prompt, "N/A"
    end

    test "prompt handles nil fundamental record" do
      prompt = Stocks::DeepAnalysisPromptBuilder.new(ticker: "AAPL", fundamental: nil).prompt
      assert_includes prompt, "AAPL"
      assert_includes prompt, "No fundamentals available"
    end

    # ── sector notes ──────────────────────────────────────────────────────────

    test "includes Technology sector notes for tech companies" do
      f = build_fundamental(sector: "Technology")
      prompt = Stocks::DeepAnalysisPromptBuilder.new(ticker: "MSFT", fundamental: f).prompt
      assert_includes prompt, "SaaS"
    end

    test "includes Financial sector notes for financial companies" do
      f = build_fundamental(sector: "Financial")
      prompt = Stocks::DeepAnalysisPromptBuilder.new(ticker: "JPM", fundamental: f).prompt
      assert_includes prompt, "CET1"
    end

    test "includes Healthcare sector notes for healthcare companies" do
      f = build_fundamental(sector: "Healthcare")
      prompt = Stocks::DeepAnalysisPromptBuilder.new(ticker: "UNH", fundamental: f).prompt
      assert_includes prompt, "biotech"
    end

    test "includes Energy sector notes for energy companies" do
      f = build_fundamental(sector: "Energy")
      prompt = Stocks::DeepAnalysisPromptBuilder.new(ticker: "XOM", fundamental: f).prompt
      assert_includes prompt, "EBITDAX"
    end

    test "includes Real Estate sector notes for REITs" do
      f = build_fundamental(sector: "Real Estate")
      prompt = Stocks::DeepAnalysisPromptBuilder.new(ticker: "AMT", fundamental: f).prompt
      assert_includes prompt, "FFO"
    end

    test "omits sector notes for unrecognised sector" do
      f = build_fundamental(sector: "Industrials")
      prompt = Stocks::DeepAnalysisPromptBuilder.new(ticker: "GE", fundamental: f).prompt
      refute_includes prompt, "Sector Note:"
    end

    test "omits sector notes when fundamental is nil" do
      prompt = Stocks::DeepAnalysisPromptBuilder.new(ticker: "GE", fundamental: nil).prompt
      refute_includes prompt, "Sector Note:"
    end

    # ── system_prompt ─────────────────────────────────────────────────────────

    test "system_prompt contains Phase 2 framework keywords" do
      builder = Stocks::DeepAnalysisPromptBuilder.new(ticker: "AAPL", fundamental: nil)
      system = builder.system_prompt
      assert_includes system.downcase, "moat"
      assert_includes system.downcase, "solvency"
      assert_includes system.downcase, "value trap"
      assert_includes system.downcase, "turnaround"
    end

    # ── tools ─────────────────────────────────────────────────────────────────

    test "tools returns web search tool" do
      builder = Stocks::DeepAnalysisPromptBuilder.new(ticker: "AAPL", fundamental: nil)
      assert_equal [ Ai::ClaudeService::WEB_SEARCH_TOOL ], builder.tools
    end

    # ── class method interface ────────────────────────────────────────────────

    test ".call returns prompt string" do
      result = Stocks::DeepAnalysisPromptBuilder.call(ticker: "AAPL", fundamental: build_fundamental)
      assert_kind_of String, result
      assert_includes result, "AAPL"
    end
  end
end
