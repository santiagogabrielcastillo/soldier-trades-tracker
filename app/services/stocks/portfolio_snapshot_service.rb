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
      @stock_portfolio.stock_portfolio_snapshots.create!(
        total_value: compute_portfolio_value,
        cash_flow: @cash_flow,
        recorded_at: Time.current,
        source: @source
      )
    end

    private

    def compute_portfolio_value
      positions = Stocks::PositionStateService.call(stock_portfolio: @stock_portfolio)
      open_positions = positions.select(&:open?)

      market_value = if open_positions.any?
        tickers = open_positions.map(&:ticker).uniq
        prices = if @stock_portfolio.argentina?
          Stocks::ArgentineCurrentPriceFetcher.call(tickers: tickers)
        else
          Stocks::CurrentPriceFetcher.call(tickers: tickers, user: @stock_portfolio.user)
        end
        open_positions.sum(BigDecimal("0")) { |pos| (prices[pos.ticker] || 0).to_d * pos.shares }
      else
        BigDecimal("0")
      end

      cash = Stocks::CashBalanceService.call(stock_portfolio: @stock_portfolio)
      market_value + cash
    end
  end
end
