# frozen_string_literal: true

module Stocks
  # Runs on the 1st of each month. Takes a portfolio snapshot for every stock portfolio.
  class MonthlySnapshotJob < ApplicationJob
    queue_as :default

    def perform
      StockPortfolio.find_each do |portfolio|
        Stocks::PortfolioSnapshotService.call(stock_portfolio: portfolio, source: "monthly")
      rescue => e
        Rails.logger.error("[Stocks::MonthlySnapshotJob] Portfolio #{portfolio.id}: #{e.message}")
      end
    end
  end
end
