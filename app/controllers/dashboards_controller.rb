# frozen_string_literal: true

require "ostruct"

class DashboardsController < ApplicationController
  def show
    result = Dashboards::SummaryService.call(current_user)
    result[:summary_trades_path] = trades_path(result[:summary_trades_path_params])
    @dashboard = OpenStruct.new(result)
  end
end
