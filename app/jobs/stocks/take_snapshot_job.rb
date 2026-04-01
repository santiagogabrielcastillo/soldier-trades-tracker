# frozen_string_literal: true

module Stocks
  # Takes a portfolio snapshot for every stock portfolio with a given source label.
  # Replaces Stocks::WeeklySnapshotJob and Stocks::MonthlySnapshotJob.
  # Schedule via config/recurring.yml:
  #   stocks_weekly_snapshot:  cron: "0 0 * * MON"  class: "Stocks::TakeSnapshotJob"  args: ["weekly"]
  #   stocks_monthly_snapshot: cron: "0 0 1 * *"    class: "Stocks::TakeSnapshotJob"  args: ["monthly"]
  class TakeSnapshotJob < ApplicationJob
    queue_as :default

    def perform(source)
      StockPortfolio.find_each do |portfolio|
        Stocks::PortfolioSnapshotService.call(stock_portfolio: portfolio, source: source)
      rescue => e
        Rails.logger.error("[Stocks::TakeSnapshotJob] Portfolio #{portfolio.id} source=#{source}: #{e.message}")
      end
    end
  end
end
