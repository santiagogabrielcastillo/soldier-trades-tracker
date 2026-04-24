# frozen_string_literal: true

class TradesController < ApplicationController
  def index
    default = current_user.default_portfolio
    if default.present? && params[:view].blank? && params[:portfolio_id].blank?
      redirect_to trades_path(view: "portfolio", portfolio_id: default.id) and return
    end

    exchange_account = resolve_exchange_account
    if params[:view].to_s == "exchange" && params[:exchange_account_id].present? && exchange_account.nil?
      redirect_to trades_path(view: "history"), alert: t("flash.exchange_account_not_found") and return
    end

    result = Trades::IndexService.call(
      user: current_user,
      view: params[:view],
      portfolio_id: params[:portfolio_id],
      exchange_account_id: exchange_account&.id,
      from_date: params[:from_date],
      to_date: params[:to_date]
    )
    @view = result[:view]
    @portfolio = result[:portfolio]
    @positions = result[:positions]
    @current_prices = result[:current_prices] || {}
    @pagy, @positions = pagy(:offset, result[:positions], limit: 25)
    @portfolios = result[:portfolios]
    @exchange_account = result[:exchange_account]
    @exchange_accounts = result[:exchange_accounts] || []
    @from_date = result[:from_date]
    @to_date = result[:to_date]
    @visible_column_ids = visible_trades_column_ids
  end

  private

  def resolve_exchange_account
    return nil if params[:exchange_account_id].blank?
    current_user.exchange_accounts.find_by(id: params[:exchange_account_id])
  end

  def visible_trades_column_ids
    tab_key = helpers.trades_index_tab_key(@view, @exchange_account&.id, @portfolio&.id)
    helpers.trades_index_visible_column_ids_for(current_user, tab_key)
  end
end
