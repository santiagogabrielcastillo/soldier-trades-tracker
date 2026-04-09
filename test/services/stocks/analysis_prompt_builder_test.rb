# frozen_string_literal: true

require "test_helper"

module Stocks
  class AnalysisPromptBuilderTest < ActiveSupport::TestCase
    def build_fundamental(overrides = {})
      StockFundamental.new(
        ticker:     overrides.fetch(:ticker,     "AAPL"),
        pe:         overrides.fetch(:pe,         BigDecimal("28.5")),
        fwd_pe:     overrides.fetch(:fwd_pe,     BigDecimal("25.1")),
        peg:        overrides.fetch(:peg,        BigDecimal("2.3")),
        ps:         overrides.fetch(:ps,         BigDecimal("7.5")),
        pfcf:       overrides.fetch(:pfcf,       BigDecimal("30.2")),
        ev_ebitda:  overrides.fetch(:ev_ebitda,  BigDecimal("22.1")),
        net_margin: overrides.fetch(:net_margin, BigDecimal("25.31")),
        roe:        overrides.fetch(:roe,        BigDecimal("147.25")),
        roic:       overrides.fetch(:roic,       BigDecimal("55.1")),
        debt_eq:    overrides.fetch(:debt_eq,    BigDecimal("1.87")),
        sales_5y:   overrides.fetch(:sales_5y,   BigDecimal("2.02")),
        sales_qq:   overrides.fetch(:sales_qq,   BigDecimal("4.87")),
        sector:     overrides.fetch(:sector,     "Technology"),
        industry:   overrides.fetch(:industry,   "Consumer Electronics"),
        fetched_at: Time.current
      )
    end

    test "prompt includes ticker symbol" do
      fundamental = build_fundamental(ticker: "AAPL")
      prompt = Stocks::AnalysisPromptBuilder.call(ticker: "AAPL", fundamental: fundamental)

      assert_includes prompt, "AAPL"
    end

    test "prompt includes sector and industry" do
      fundamental = build_fundamental(sector: "Technology", industry: "Consumer Electronics")
      prompt = Stocks::AnalysisPromptBuilder.call(ticker: "AAPL", fundamental: fundamental)

      assert_includes prompt, "Technology"
      assert_includes prompt, "Consumer Electronics"
    end

    test "prompt includes key financial metrics" do
      fundamental = build_fundamental(pe: BigDecimal("28.5"), roe: BigDecimal("147.25"))
      prompt = Stocks::AnalysisPromptBuilder.call(ticker: "AAPL", fundamental: fundamental)

      assert_includes prompt, "28.5"
      assert_includes prompt, "147.25"
    end

    test "prompt requests JSON output" do
      fundamental = build_fundamental
      prompt = Stocks::AnalysisPromptBuilder.call(ticker: "AAPL", fundamental: fundamental)

      assert_includes prompt, '"rating"'
      assert_includes prompt, '"executive_summary"'
      assert_includes prompt, '"thesis_breakdown"'
      assert_includes prompt, '"red_flags"'
    end

    test "prompt handles nil fundamentals gracefully" do
      fundamental = build_fundamental(pe: nil, sector: nil, ev_ebitda: nil)
      prompt = Stocks::AnalysisPromptBuilder.call(ticker: "AAPL", fundamental: fundamental)

      assert_includes prompt, "N/A"
      assert_includes prompt, "AAPL"
    end

    test "prompt handles nil fundamental record" do
      prompt = Stocks::AnalysisPromptBuilder.call(ticker: "AAPL", fundamental: nil)

      assert_includes prompt, "AAPL"
      assert_includes prompt, "N/A"
    end
  end
end
