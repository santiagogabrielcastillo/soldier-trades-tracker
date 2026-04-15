# frozen_string_literal: true

class StockAnalysisCardComponent < ApplicationComponent
  def initialize(analysis:, fundamental: nil)
    @analysis    = analysis
    @fundamental = fundamental
    @data        = analysis.structured_data || {}
  end

  def deep?
    @data.present?
  end

  # ── Verdict ──────────────────────────────────────────────────────────────
  def verdict
    @data["verdict"] || @analysis.rating || "watch"
  end

  def verdict_label
    @data["verdict_label"] || verdict.capitalize
  end

  def verdict_banner_css
    case verdict
    when "buy", "accumulate" then "bg-emerald-600 text-white"
    when "hold"              then "bg-amber-500 text-white"
    when "watch"             then "bg-slate-700 text-white"
    when "sell"              then "bg-red-600 text-white"
    else                          "bg-slate-700 text-white"
    end
  end

  def verdict_dot_css
    case verdict
    when "buy", "accumulate" then "bg-emerald-300"
    when "hold"              then "bg-amber-300"
    when "watch"             then "bg-slate-400"
    when "sell"              then "bg-red-300"
    else                          "bg-slate-400"
    end
  end

  # ── Metrics ───────────────────────────────────────────────────────────────
  def metrics
    @data["metrics"] || {}
  end

  METRIC_LABELS = {
    "price"               => "Price",
    "market_cap"          => "Market Cap",
    "forward_pe"          => "Forward P/E",
    "ev_revenue"          => "EV / Revenue",
    "net_debt_ebitda"     => "Net Debt / EBITDA",
    "fcf_margin"          => "FCF Margin",
    "renewal_or_retention" => "Retention",
    "revenue_growth"      => "Revenue Growth"
  }.freeze

  def metric_status_css(status)
    case status.to_s
    when "excellent"  then "text-emerald-600"
    when "acceptable" then "text-sky-600"
    when "warning"    then "text-amber-600"
    when "red_flag"   then "text-red-600"
    else                   "text-slate-800"
    end
  end

  # ── Moat ──────────────────────────────────────────────────────────────────
  def moat
    @data["moat"] || {}
  end

  MOAT_LABELS = {
    "switching_costs" => "Switching Costs",
    "scale_advantage" => "Scale Advantage",
    "network_effect"  => "Network Effect",
    "intangibles"     => "Intangibles"
  }.freeze

  def moat_overall_css
    case moat["overall"].to_s
    when "wide"   then "text-emerald-600"
    when "narrow" then "text-amber-600"
    when "none"   then "text-red-500"
    else               "text-slate-500"
    end
  end

  # ── Revenue trend ─────────────────────────────────────────────────────────
  def revenue_trend
    @data["revenue_trend"] || []
  end

  def revenue_unit
    @data["revenue_unit"] || "B"
  end

  def revenue_max
    @_revenue_max ||= (revenue_trend.map { |r| r["revenue"].to_f }.max || 0).then { |m| m.zero? ? 1 : m }
  end

  def fcf_max
    @_fcf_max ||= revenue_trend.map { |r| r["fcf"].to_f }.max.then { |m| m.zero? ? 1 : m }
  end

  # ── Tags ──────────────────────────────────────────────────────────────────
  def tags
    @data["tags"] || []
  end

  def tag_css(color)
    case color.to_s
    when "green" then "bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200"
    when "amber" then "bg-amber-50 text-amber-700 ring-1 ring-amber-200"
    when "red"   then "bg-red-50 text-red-700 ring-1 ring-red-200"
    else              "bg-slate-100 text-slate-700 ring-1 ring-slate-200"
    end
  end

  # ── Asset / Turnaround ────────────────────────────────────────────────────
  def asset_classification
    @data["asset_classification"] || "—"
  end

  def turnaround_mode?
    @data["turnaround_mode"] == true
  end

  def turnaround_label
    case @data["turnaround_bucket"].to_s
    when "reversible_operational_stress"  then "Reversible Operational Stress"
    when "structural_franchise_damage"    then "Structural Franchise Damage"
    when "unresolvable_legal_uncertainty" then "Unresolvable Legal Uncertainty"
    else "Turnaround"
    end
  end

  # ── Prose ─────────────────────────────────────────────────────────────────
  def executive_summary
    (@data["executive_summary"] || @analysis.executive_summary).to_s
  end

  def thesis_breakdown
    (@data["thesis_breakdown"] || @analysis.thesis_breakdown).to_s
  end

  def risk_reward_rating
    (@data["risk_reward_rating"] || @analysis.risk_reward_rating).to_s
  end

  def red_flags
    (@data["red_flags"] || @analysis.red_flags).to_s
  end

  def what_to_watch
    @data["what_to_watch"].to_s
  end

  def sources
    Array(@data["sources"]).reject(&:blank?)
  end

  def company_name
    @data["company_name"] || @analysis.ticker
  end

  def analyzed_at_formatted
    @analysis.analyzed_at.strftime("%B %-d, %Y")
  end

  def provider_badge
    @analysis.provider == "claude" ? "Claude · Web Search" : "Gemini"
  end
end
