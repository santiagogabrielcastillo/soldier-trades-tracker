# frozen_string_literal: true

module Stocks
  # Runs every Monday. Takes a portfolio snapshot for every stock portfolio,
  # so TWR can be tracked week-over-week.
  class WeeklySnapshotJob < ApplicationJob
    queue_as :default

    def perform
      StockPortfolio.find_each do |portfolio|
        Stocks::PortfolioSnapshotService.call(stock_portfolio: portfolio, source: "weekly")
      rescue => e
        Rails.logger.error("[Stocks::WeeklySnapshotJob] Portfolio #{portfolio.id}: #{e.message}")
      end
    end
  end
end
