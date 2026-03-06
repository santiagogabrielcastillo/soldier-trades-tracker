# frozen_string_literal: true

class UserPreferencesController < ApplicationController
  def update_trades_index_columns
    column_ids = params[:column_ids].to_a.map(&:to_s)
    allowed = TradesIndexColumns::ALL_IDS
    column_ids = column_ids.select { |id| allowed.include?(id) }.uniq

    if column_ids.empty?
      redirect_back fallback_location: trades_path, alert: "Select at least one column."
      return
    end

    pref = current_user.user_preferences.find_or_initialize_by(key: "trades_index_visible_columns")
    pref.value = column_ids
    if pref.save
      redirect_to trades_path(view: params[:view], portfolio_id: params[:portfolio_id]), notice: "Columns saved."
    else
      redirect_back fallback_location: trades_path, alert: "Could not save columns."
    end
  end
end
