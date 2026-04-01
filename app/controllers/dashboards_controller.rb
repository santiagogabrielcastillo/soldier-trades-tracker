# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    mep_rate = begin
      Stocks::MepRateFetcher.call
    rescue StandardError => e
      Rails.logger.warn("[DashboardsController] MEP rate unavailable: #{e.message}")
      nil
    end

    summary_thread    = Thread.new { Dashboards::SummaryService.call(current_user, mep_rate: mep_rate) }
    allocation_thread = Thread.new { Allocations::SummaryService.call(user: current_user, mep_rate: mep_rate) }

    result = summary_thread.value
    result[:summary_trades_path] = trades_path(result[:summary_trades_path_params])
    @dashboard = Struct.new(*result.keys, keyword_init: true).new(**result)

    @allocation_summary = allocation_thread.value
  end
end
