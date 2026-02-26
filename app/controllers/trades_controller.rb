# frozen_string_literal: true

class TradesController < ApplicationController
  def index
    @trades = current_user.trades.order(executed_at: :desc).limit(500)
  end
end
