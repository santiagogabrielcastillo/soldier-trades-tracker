# frozen_string_literal: true

class ManualTradesController < ApplicationController
  before_action :set_account
  before_action :set_trade, only: %i[edit update destroy]

  def new
    @trade = ManualTrade.new
  end

  def create
    @trade = ManualTrade.new(manual_trade_params)
    @trade.exchange_account = @account
    if @trade.save
      Positions::RebuildForAccountService.call(@account)
      redirect_to exchange_accounts_path, notice: "Trade added and positions rebuilt."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @trade.assign_from_params(manual_trade_params)
    if @trade.save
      Positions::RebuildForAccountService.call(@account)
      redirect_to exchange_accounts_path, notice: "Trade updated and positions rebuilt."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @trade.trade_record.destroy
    Positions::RebuildForAccountService.call(@account)
    redirect_to exchange_accounts_path, notice: "Trade deleted and positions rebuilt."
  end

  private

  def set_account
    @account = current_user.exchange_accounts.find(params[:exchange_account_id])
  end

  def set_trade
    trade = @account.trades.find(params[:id])
    unless trade.manual?
      redirect_to exchange_accounts_path, alert: "Only manually-entered trades can be edited."
      return
    end
    @trade = ManualTrade.from_trade(trade)
  end

  def manual_trade_params
    params.require(:manual_trade).permit(
      :symbol, :side, :quantity, :price, :executed_at,
      :fee, :position_side, :leverage, :reduce_only, :realized_pnl
    )
  end
end
