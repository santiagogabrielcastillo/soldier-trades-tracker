# frozen_string_literal: true

class UserPreferencesController < ApplicationController
  def update_trades_index_columns
    column_ids = params[:column_ids].to_a.map(&:to_s)
    allowed = TradesIndexColumns::ALL_IDS
    column_ids = column_ids.select { |id| allowed.include?(id) }.uniq

    if column_ids.empty?
      redirect_back fallback_location: trades_path, alert: t("flash.columns_at_least_one")
      return
    end

    exchange_account = resolve_exchange_account_for_columns
    portfolio = resolve_portfolio_for_columns

    if params[:view].to_s == "exchange" && params[:exchange_account_id].present? && exchange_account.nil?
      redirect_back fallback_location: trades_path, alert: t("flash.columns_exchange_not_found") and return
    end
    if params[:view].to_s == "portfolio" && params[:portfolio_id].present? && portfolio.nil?
      redirect_back fallback_location: trades_path, alert: t("flash.columns_portfolio_not_found") and return
    end

    tab_key = helpers.trades_index_tab_key(params[:view], exchange_account&.id, portfolio&.id)
    pref = current_user.user_preferences.find_or_initialize_by(key: "trades_index_visible_columns:#{tab_key}")
    pref.value = column_ids
    if pref.save
      redirect_params = params.permit(TradesHelper::TRADES_INDEX_PARAMS).to_h.compact_blank
      redirect_to trades_path(redirect_params), notice: t("flash.columns_saved")
    else
      redirect_back fallback_location: trades_path, alert: t("flash.columns_could_not_save")
    end
  end

  private

  def resolve_exchange_account_for_columns
    return nil if params[:exchange_account_id].blank?
    current_user.exchange_accounts.find_by(id: params[:exchange_account_id])
  end

  def resolve_portfolio_for_columns
    return nil if params[:portfolio_id].blank?
    current_user.portfolios.find_by(id: params[:portfolio_id])
  end
end
