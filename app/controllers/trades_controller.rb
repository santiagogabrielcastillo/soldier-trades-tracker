# frozen_string_literal: true

class TradesController < ApplicationController
  def index
    trades = current_user.trades.includes(:exchange_account).order(executed_at: :asc).limit(2000)
    @positions = PositionSummary.from_trades(trades)
    PositionSummary.assign_balance!(@positions)
  end
end
