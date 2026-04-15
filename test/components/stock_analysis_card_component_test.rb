# frozen_string_literal: true

require "test_helper"

class StockAnalysisCardComponentTest < ViewComponent::TestCase
  DEEP_DATA = {
    "verdict"         => "buy",
    "verdict_label"   => "Buy — strong fundamentals at cyclical low",
    "company_name"    => "Apple Inc.",
    "analyzed_at"     => "2026-04-15",
    "metrics" => {
      "price"               => { "value" => "$175", "subtitle" => "-10% from 52w high" },
      "market_cap"          => { "value" => "$2.7T", "subtitle" => "15.4B shares" },
      "forward_pe"          => { "value" => "25x", "subtitle" => "vs 5y avg 28x" },
      "ev_revenue"          => { "value" => "7.5x", "subtitle" => "vs median 8x" },
      "net_debt_ebitda"     => { "value" => "Net cash", "subtitle" => "$60B cash vs $10B debt", "status" => "excellent" },
      "fcf_margin"          => { "value" => "26%", "subtitle" => "$100B FCF" },
      "renewal_or_retention" => { "value" => "98%", "subtitle" => "Multi-year streak" },
      "revenue_growth"      => { "value" => "4%", "subtitle" => "FY25 YoY" }
    },
    "moat" => {
      "overall" => "wide",
      "scores" => {
        "switching_costs" => { "score" => 5, "max" => 5 },
        "scale_advantage" => { "score" => 4, "max" => 5 },
        "network_effect"  => { "score" => 3, "max" => 5 },
        "intangibles"     => { "score" => 5, "max" => 5 }
      },
      "primary_threat" => "AI disruption to hardware replacement cycle"
    },
    "revenue_trend" => [
      { "year" => "FY21", "revenue" => 365.8, "fcf" => 93.0 },
      { "year" => "FY22", "revenue" => 394.3, "fcf" => 111.4 },
      { "year" => "FY23", "revenue" => 383.3, "fcf" => 99.6 },
      { "year" => "FY24", "revenue" => 391.0, "fcf" => 108.8 },
      { "year" => "FY25", "revenue" => 395.0, "fcf" => 103.0 }
    ],
    "revenue_unit" => "B",
    "tags" => [
      { "label" => "Asset light",      "color" => "green" },
      { "label" => "Net cash",         "color" => "green" },
      { "label" => "AI risk",          "color" => "amber" },
      { "label" => "SBC ~3% of rev",   "color" => "red" }
    ],
    "asset_classification" => "light",
    "turnaround_mode"      => false,
    "turnaround_bucket"    => nil,
    "executive_summary"    => "Apple is a consumer electronics giant with a deep ecosystem moat.",
    "thesis_breakdown"     => "Detailed moat and valuation analysis goes here.",
    "risk_reward_rating"   => "Excellent — strong balance sheet.",
    "red_flags"            => "1. Slowing iPhone growth.\n2. China concentration risk.",
    "what_to_watch"        => "Q2 FY26 earnings on May 1.",
    "sources"              => [ "https://example.com/aapl-analysis" ]
  }.freeze

  def build_analysis(overrides = {})
    StockAnalysis.new(
      ticker:             "AAPL",
      rating:             overrides.fetch(:rating, "buy"),
      executive_summary:  overrides.fetch(:executive_summary, "Test summary."),
      risk_reward_rating: overrides.fetch(:risk_reward_rating, "Good"),
      thesis_breakdown:   overrides.fetch(:thesis_breakdown, "Test thesis."),
      red_flags:          overrides.fetch(:red_flags, "None"),
      structured_data:    overrides.fetch(:structured_data, DEEP_DATA),
      provider:           overrides.fetch(:provider, "claude"),
      analyzed_at:        overrides.fetch(:analyzed_at, Time.current),
      user:               users(:one)
    )
  end

  # ── deep? ─────────────────────────────────────────────────────────────────

  test "deep? is true when structured_data is present" do
    component = StockAnalysisCardComponent.new(analysis: build_analysis)
    assert component.deep?
  end

  test "deep? is false when structured_data is nil" do
    component = StockAnalysisCardComponent.new(analysis: build_analysis(structured_data: nil))
    refute component.deep?
  end

  # ── verdict helpers ───────────────────────────────────────────────────────

  test "verdict_banner_css is emerald for buy" do
    component = StockAnalysisCardComponent.new(analysis: build_analysis)
    assert_includes component.verdict_banner_css, "emerald"
  end

  test "verdict_banner_css is emerald for accumulate" do
    component = StockAnalysisCardComponent.new(analysis: build_analysis(structured_data: DEEP_DATA.merge("verdict" => "accumulate")))
    assert_includes component.verdict_banner_css, "emerald"
  end

  test "verdict_banner_css is amber for hold" do
    component = StockAnalysisCardComponent.new(analysis: build_analysis(structured_data: DEEP_DATA.merge("verdict" => "hold")))
    assert_includes component.verdict_banner_css, "amber"
  end

  test "verdict_banner_css is red for sell" do
    component = StockAnalysisCardComponent.new(analysis: build_analysis(structured_data: DEEP_DATA.merge("verdict" => "sell")))
    assert_includes component.verdict_banner_css, "red"
  end

  test "verdict falls back to analysis rating when no structured_data" do
    analysis = build_analysis(structured_data: nil, rating: "hold")
    component = StockAnalysisCardComponent.new(analysis: analysis)
    assert_equal "hold", component.verdict
  end

  # ── moat helpers ──────────────────────────────────────────────────────────

  test "moat_overall_css is emerald for wide moat" do
    component = StockAnalysisCardComponent.new(analysis: build_analysis)
    assert_includes component.moat_overall_css, "emerald"
  end

  test "moat_overall_css is amber for narrow moat" do
    narrow = DEEP_DATA.deep_dup.tap { |d| d["moat"]["overall"] = "narrow" }
    component = StockAnalysisCardComponent.new(analysis: build_analysis(structured_data: narrow))
    assert_includes component.moat_overall_css, "amber"
  end

  test "moat_overall_css is red for no moat" do
    none = DEEP_DATA.deep_dup.tap { |d| d["moat"]["overall"] = "none" }
    component = StockAnalysisCardComponent.new(analysis: build_analysis(structured_data: none))
    assert_includes component.moat_overall_css, "red"
  end

  # ── metric_status_css ────────────────────────────────────────────────────

  test "metric_status_css maps statuses to color classes" do
    component = StockAnalysisCardComponent.new(analysis: build_analysis)
    assert_includes component.metric_status_css("excellent"),  "emerald"
    assert_includes component.metric_status_css("acceptable"), "sky"
    assert_includes component.metric_status_css("warning"),    "amber"
    assert_includes component.metric_status_css("red_flag"),   "red"
  end

  # ── tag_css ───────────────────────────────────────────────────────────────

  test "tag_css maps tag colors correctly" do
    component = StockAnalysisCardComponent.new(analysis: build_analysis)
    assert_includes component.tag_css("green"), "emerald"
    assert_includes component.tag_css("amber"), "amber"
    assert_includes component.tag_css("red"),   "red"
  end

  # ── turnaround helpers ───────────────────────────────────────────────────

  test "turnaround_mode? is false for normal analysis" do
    component = StockAnalysisCardComponent.new(analysis: build_analysis)
    refute component.turnaround_mode?
  end

  test "turnaround_mode? is true when flag set" do
    turnaround_data = DEEP_DATA.merge("turnaround_mode" => true, "turnaround_bucket" => "reversible_operational_stress")
    component = StockAnalysisCardComponent.new(analysis: build_analysis(structured_data: turnaround_data))
    assert component.turnaround_mode?
  end

  test "turnaround_label returns human-readable string" do
    data = DEEP_DATA.merge("turnaround_bucket" => "unresolvable_legal_uncertainty")
    component = StockAnalysisCardComponent.new(analysis: build_analysis(structured_data: data))
    assert_equal "Unresolvable Legal Uncertainty", component.turnaround_label
  end

  # ── revenue helpers ───────────────────────────────────────────────────────

  test "revenue_max returns largest revenue value" do
    component = StockAnalysisCardComponent.new(analysis: build_analysis)
    assert_equal 395.0, component.revenue_max
  end

  test "revenue_max is 1 when no trend data to avoid divide by zero" do
    empty = DEEP_DATA.merge("revenue_trend" => [])
    component = StockAnalysisCardComponent.new(analysis: build_analysis(structured_data: empty))
    assert_equal 1, component.revenue_max
  end

  # ── prose fallbacks ────────────────────────────────────────────────────────

  test "prose fields fall back to analysis columns when structured_data nil" do
    analysis = build_analysis(
      structured_data:    nil,
      executive_summary:  "Fallback summary",
      thesis_breakdown:   "Fallback thesis",
      red_flags:          "Fallback flags"
    )
    component = StockAnalysisCardComponent.new(analysis: analysis)
    assert_equal "Fallback summary", component.executive_summary
    assert_equal "Fallback thesis",  component.thesis_breakdown
    assert_equal "Fallback flags",   component.red_flags
  end

  # ── rendering ─────────────────────────────────────────────────────────────

  test "renders company name" do
    render_inline(StockAnalysisCardComponent.new(analysis: build_analysis))
    assert_text "Apple Inc."
  end

  test "renders verdict in uppercase" do
    render_inline(StockAnalysisCardComponent.new(analysis: build_analysis))
    assert_text "BUY"
  end

  test "renders verdict label" do
    render_inline(StockAnalysisCardComponent.new(analysis: build_analysis))
    assert_text "Buy — strong fundamentals at cyclical low"
  end

  test "renders metric values" do
    render_inline(StockAnalysisCardComponent.new(analysis: build_analysis))
    assert_text "$175"
    assert_text "$2.7T"
  end

  test "renders moat dimensions" do
    render_inline(StockAnalysisCardComponent.new(analysis: build_analysis))
    assert_text "Switching Costs"
    assert_text "Scale Advantage"
  end

  test "renders revenue trend years" do
    render_inline(StockAnalysisCardComponent.new(analysis: build_analysis))
    assert_text "FY21"
    assert_text "FY25"
  end

  test "renders tags" do
    render_inline(StockAnalysisCardComponent.new(analysis: build_analysis))
    assert_text "Asset light"
    assert_text "Net cash"
    assert_text "AI risk"
  end

  test "renders executive summary in open details section" do
    render_inline(StockAnalysisCardComponent.new(analysis: build_analysis))
    assert_text "Apple is a consumer electronics giant"
  end

  test "renders red flags section" do
    render_inline(StockAnalysisCardComponent.new(analysis: build_analysis))
    assert_text "Red Flags"
    assert_text "Slowing iPhone growth"
  end

  test "renders sources" do
    render_inline(StockAnalysisCardComponent.new(analysis: build_analysis))
    assert_text "https://example.com/aapl-analysis"
  end

  test "renders provider badge for claude" do
    render_inline(StockAnalysisCardComponent.new(analysis: build_analysis))
    assert_text "Claude · Web Search"
  end

  test "renders provider badge for gemini" do
    analysis = build_analysis(provider: "gemini", structured_data: nil)
    render_inline(StockAnalysisCardComponent.new(analysis: analysis))
    assert_text "Gemini"
  end

  test "renders turnaround pill when turnaround_mode is true" do
    data = DEEP_DATA.merge("turnaround_mode" => true, "turnaround_bucket" => "reversible_operational_stress")
    render_inline(StockAnalysisCardComponent.new(analysis: build_analysis(structured_data: data)))
    assert_text "Turnaround"
    assert_text "Reversible Operational Stress"
  end

  test "does not render metric grid when no structured_data" do
    analysis = build_analysis(structured_data: nil)
    render_inline(StockAnalysisCardComponent.new(analysis: analysis))
    assert_no_text "Key Metrics"
  end

  test "still renders prose sections when no structured_data" do
    analysis = build_analysis(structured_data: nil, executive_summary: "Fallback summary text")
    render_inline(StockAnalysisCardComponent.new(analysis: analysis))
    assert_text "Fallback summary text"
  end
end
