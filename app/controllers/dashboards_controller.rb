# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    @exchange_accounts = current_user.exchange_accounts
    @default_portfolio = current_user.default_portfolio

    if @default_portfolio
      trades = @default_portfolio.trades_in_range.includes(:exchange_account).order(executed_at: :asc).limit(2000)
      positions = PositionSummary.from_trades(trades)
      PositionSummary.assign_balance!(positions, initial_balance: @default_portfolio.initial_balance.to_d)
      @summary_label = @default_portfolio.name
      @summary_date_range = @default_portfolio.date_range_label
      @summary_period_pl = positions.sum(&:net_pl)
      @summary_balance = @default_portfolio.initial_balance.to_d + @summary_period_pl
      @summary_position_count = positions.size
      @summary_trades_path = trades_path(view: "portfolio", portfolio_id: @default_portfolio.id)
    else
      trades = current_user.trades.includes(:exchange_account).order(executed_at: :asc).limit(2000)
      positions = PositionSummary.from_trades(trades)
      PositionSummary.assign_balance!(positions)
      @summary_label = "All time"
      @summary_date_range = nil
      @summary_period_pl = positions.sum(&:net_pl)
      @summary_balance = @summary_period_pl
      @summary_position_count = positions.size
      @summary_trades_path = trades_path(view: "history")
    end
  end
end
