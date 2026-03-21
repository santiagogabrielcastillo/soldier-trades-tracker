# frozen_string_literal: true

module Stocks
  # Computes Time-Weighted Return (TWR) from a portfolio's ordered snapshots.
  #
  # Each snapshot stores total_value (BEFORE any cash flow) and cash_flow.
  # Sub-period formula:
  #   start_value = entry_i.total_value + entry_i.cash_flow   (after CF at tᵢ)
  #   Rᵢ          = (entry_next.total_value - start_value) / start_value
  #   TWR         = ∏(1 + Rᵢ) − 1
  #
  # Returns Array<{date: String, twr_pct: Float}> — cumulative TWR at each point.
  class TwrCalculatorService
    TwrPoint = Struct.new(:date, :twr_pct, keyword_init: true)

    def self.call(stock_portfolio:)
      new(stock_portfolio: stock_portfolio).call
    end

    def initialize(stock_portfolio:)
      @stock_portfolio = stock_portfolio
    end

    def call
      entries = @stock_portfolio.stock_portfolio_snapshots.ordered.to_a
      return [] if entries.size < 2

      twr = BigDecimal("1")
      result = []

      entries.each_cons(2) do |prev_entry, curr_entry|
        start_value = prev_entry.total_value.to_d + prev_entry.cash_flow.to_d
        next if start_value.zero?

        sub_period_return = (curr_entry.total_value.to_d - start_value) / start_value
        twr *= (1 + sub_period_return)

        result << TwrPoint.new(
          date: curr_entry.recorded_at.to_date.to_s,
          twr_pct: ((twr - 1) * 100).round(2).to_f
        )
      end

      result
    end
  end
end
