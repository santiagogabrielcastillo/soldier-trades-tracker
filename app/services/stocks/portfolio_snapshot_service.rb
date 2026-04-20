# frozen_string_literal: true

module Stocks
  # Fetches current portfolio value and saves a StockPortfolioSnapshot.
  # cash_flow: amount deposited (+) or withdrawn (−) at this moment; 0 for pure snapshots.
  class PortfolioSnapshotService
    def self.call(stock_portfolio:, cash_flow: 0, source: "manual")
      new(stock_portfolio: stock_portfolio, cash_flow: cash_flow, source: source).call
    end

    def initialize(stock_portfolio:, cash_flow:, source:)
      @stock_portfolio = stock_portfolio
      @cash_flow = cash_flow.to_d
      @source = source
    end

    def call
      total_value = compute_portfolio_value
      @stock_portfolio.stock_portfolio_snapshots.create!(
        total_value: total_value,
        cash_flow: @cash_flow,
        recorded_at: Time.current,
        source: @source,
        positions_data: @positions_data
      )
    end

    private

    def compute_portfolio_value
      positions = Stocks::PositionStateService.call(stock_portfolio: @stock_portfolio)
      open_positions = positions.select(&:open?)
      position_entries = []

      market_value = if open_positions.any?
        tickers = open_positions.map(&:ticker).uniq
        prices = if @stock_portfolio.argentina?
          Stocks::ArgentineCurrentPriceFetcher.call(tickers: tickers, user: @stock_portfolio.user)
        else
          Stocks::CurrentPriceFetcher.call(tickers: tickers, user: @stock_portfolio.user)
        end
        open_positions.sum(BigDecimal("0")) do |pos|
          price = prices[pos.ticker]
          next BigDecimal("0") unless price
          value = price.to_d * pos.shares
          position_entries << { "ticker" => pos.ticker, "value" => value.to_f }
          value
        end
      else
        BigDecimal("0")
      end

      cash = Stocks::CashBalanceService.call(stock_portfolio: @stock_portfolio)
      position_entries << { "ticker" => "CASH", "value" => cash.to_f } if cash.nonzero?

      total = market_value + cash

      @positions_data = if total.positive?
        position_entries.map do |entry|
          entry.merge("pct_of_total" => (entry["value"] / total.to_f * 100).round(2))
        end
      else
        []
      end

      total
    end
  end
end
