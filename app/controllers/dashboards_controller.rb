# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    result = Dashboards::SummaryService.call(current_user)
    @exchange_accounts = result[:exchange_accounts]
    @default_portfolio = result[:default_portfolio]
    @summary_label = result[:summary_label]
    @summary_date_range = result[:summary_date_range]
    @summary_period_pl = result[:summary_period_pl]
    @summary_balance = result[:summary_balance]
    @summary_position_count = result[:summary_position_count]
    @summary_trades_path = trades_path(result[:summary_trades_path_params])
    @summary_total_return_pct = result[:summary_total_return_pct]
    @summary_win_rate = result[:summary_win_rate]
    @summary_avg_win = result[:summary_avg_win]
    @summary_avg_loss = result[:summary_avg_loss]
    @summary_closed_count = result[:summary_closed_count]
    @chart_balance_series = result[:chart_balance_series]
    @chart_cumulative_pl_series = result[:chart_cumulative_pl_series]
  end
end
