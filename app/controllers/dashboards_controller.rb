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
  end
end
