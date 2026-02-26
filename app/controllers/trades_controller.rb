# frozen_string_literal: true

class TradesController < ApplicationController
  def index
    @view = params[:view].to_s == "portfolio" ? "portfolio" : "history"
    @portfolio = nil
    initial_balance = 0

    if @view == "portfolio" && params[:portfolio_id].present?
      @portfolio = current_user.portfolios.find_by(id: params[:portfolio_id])
      if @portfolio
        trades = @portfolio.trades_in_range.includes(:exchange_account).order(executed_at: :asc).limit(2000)
        @positions = PositionSummary.from_trades(trades)
        initial_balance = @portfolio.initial_balance.to_d
      else
        trades = current_user.trades.includes(:exchange_account).order(executed_at: :asc).limit(2000)
        @positions = PositionSummary.from_trades(trades)
      end
    else
      trades = current_user.trades.includes(:exchange_account).order(executed_at: :asc).limit(2000)
      @positions = PositionSummary.from_trades(trades)
    end

    PositionSummary.assign_balance!(@positions, initial_balance: initial_balance)
    @portfolios = current_user.portfolios.default_first if @view == "portfolio"
  end
end
