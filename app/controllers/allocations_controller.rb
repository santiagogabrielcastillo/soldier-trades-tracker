# frozen_string_literal: true

class AllocationsController < ApplicationController
  def show
    mep_rate   = Stocks::MepRateFetcher.call rescue nil
    @summary   = Allocations::SummaryService.call(user: current_user, mep_rate: mep_rate)
    @buckets   = current_user.allocation_buckets.ordered
    @stock_portfolios = current_user.stock_portfolios.order(:name)
    @spot_accounts    = current_user.spot_accounts.order(:name)
    @new_bucket = AllocationBucket.new
    @new_entry  = AllocationManualEntry.new
  end

  def assign_stock_portfolio
    portfolio = current_user.stock_portfolios.find(params[:id])
    portfolio.update!(allocation_bucket_id: params[:allocation_bucket_id].presence)
    redirect_to allocation_path, notice: "Portfolio assigned."
  end

  def assign_spot_account
    account = current_user.spot_accounts.find(params[:id])
    account.update!(allocation_bucket_id: params[:allocation_bucket_id].presence)
    redirect_to allocation_path, notice: "Account assigned."
  end
end
