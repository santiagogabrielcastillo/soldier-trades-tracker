# frozen_string_literal: true

class TradesController < ApplicationController
  def index
    default = current_user.default_portfolio
    if default.present? && params[:view].blank? && params[:portfolio_id].blank?
      redirect_to trades_path(view: "portfolio", portfolio_id: default.id) and return
    end

    result = Trades::IndexService.call(
      user: current_user,
      view: params[:view],
      portfolio_id: params[:portfolio_id]
    )
    @view = result[:view]
    @portfolio = result[:portfolio]
    @positions = result[:positions]
    @current_prices = result[:current_prices] || {}
    @pagy, @positions = pagy(:offset, result[:positions], limit: 25)
    @portfolios = result[:portfolios]
    @visible_column_ids = visible_trades_column_ids
  end

  private

  def visible_trades_column_ids
    pref = current_user.user_preferences.find_by(key: "trades_index_visible_columns")
    TradesIndexColumns.visible_columns(pref&.value)
  end
end
