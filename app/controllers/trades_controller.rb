# frozen_string_literal: true

class TradesController < ApplicationController
  def index
    # Land on portfolio view with default portfolio when user has one and no params given
    default = current_user.default_portfolio
    if default.present? && params[:view].blank? && params[:portfolio_id].blank?
      redirect_to trades_path(view: "portfolio", portfolio_id: default.id) and return
    end

    @view = params[:view].to_s == "portfolio" ? "portfolio" : "history"
    @portfolio = if @view == "portfolio" && params[:portfolio_id].present?
      current_user.portfolios.find_by(id: params[:portfolio_id])
    elsif @view == "portfolio" && default.present?
      default
    end

    trades = if @portfolio
      @portfolio.trades_in_range.includes(:exchange_account).order(executed_at: :asc).limit(2000)
    else
      current_user.trades.includes(:exchange_account).order(executed_at: :asc).limit(2000)
    end
    @positions = PositionSummary.from_trades(trades)
    initial_balance = @portfolio&.initial_balance.to_d

    PositionSummary.assign_balance!(@positions, initial_balance: initial_balance)
    @pagy, @positions = pagy(:offset, @positions, limit: 25)
    @portfolios = current_user.portfolios.default_first if @view == "portfolio"
  end
end
