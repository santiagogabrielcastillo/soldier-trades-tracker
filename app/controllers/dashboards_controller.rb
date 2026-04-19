# frozen_string_literal: true

class DashboardsController < ApplicationController
  def show
    unless current_user.api_key_for(:coingecko)
      flash.now[:alert] = "Crypto spot prices require a CoinGecko API key. #{view_context.link_to('Configure it here', settings_api_keys_path, class: 'underline')}".html_safe
    end

    mep_rate = begin
      Stocks::MepRateFetcher.call
    rescue StandardError => e
      Rails.logger.warn("[DashboardsController] MEP rate unavailable: #{e.message}")
      nil
    end

    summary_thread    = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Dashboards::SummaryService.call(current_user)
      end
    end
    allocation_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Allocations::SummaryService.call(user: current_user, mep_rate: mep_rate)
      end
    end

    begin
      result = summary_thread.value
      result[:summary_trades_path] = trades_path(result[:summary_trades_path_params])
      @dashboard = Struct.new(*result.keys, keyword_init: true).new(**result)

      @allocation_summary = allocation_thread.value
    ensure
      # Guarantee both threads are joined and their connections returned even if one raises.
      [summary_thread, allocation_thread].each { |t| t.join rescue nil }
    end
  end
end
