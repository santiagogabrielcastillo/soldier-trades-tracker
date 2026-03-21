# frozen_string_literal: true

module Stocks
  # Computes the current cash balance held inside a stock portfolio.
  #
  # Cash = sell proceeds − buy costs + deposits − withdrawals
  #
  # Sources:
  #   • StockTrade: sell side adds cash; buy side subtracts cash (total_value_usd column)
  #   • StockPortfolioSnapshot.cash_flow: manual deposits (+) and withdrawals (−)
  #
  # Returns a BigDecimal (can be negative if deposits were never recorded).
  class CashBalanceService
    def self.call(stock_portfolio:)
      trade_delta = stock_portfolio.stock_trades.sum(
        "CASE WHEN side = 'sell' THEN total_value_usd ELSE -total_value_usd END"
      ).to_d

      cf_delta = stock_portfolio.stock_portfolio_snapshots.sum(:cash_flow).to_d

      trade_delta + cf_delta
    end
  end
end
