# frozen_string_literal: true

class ExchangeAccountsController < ApplicationController
  before_action :set_exchange_account, only: %i[destroy sync]

  def index
    @pagy, @exchange_accounts = pagy(:offset, current_user.exchange_accounts, limit: 25)
  end

  def new
    @exchange_account = current_user.exchange_accounts.build
  end

  def create
    @exchange_account = current_user.exchange_accounts.build(exchange_account_params)
    if @exchange_account.api_key.blank? || @exchange_account.api_secret.blank?
      @exchange_account.errors.add(:base, "API key and secret are required.")
      render :new, status: :unprocessable_entity
      return
    end
    @exchange_account.linked_at = Time.current
    if @exchange_account.save
      redirect_to exchange_accounts_path, notice: "Exchange account linked successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @exchange_account.destroy
    redirect_to exchange_accounts_path, notice: "Exchange account removed."
  end

  def sync
    if @exchange_account.provider_type != "bingx"
      redirect_to exchange_accounts_path, alert: "Only BingX accounts can be synced."
      return
    end
    unless @exchange_account.can_sync?
      redirect_to exchange_accounts_path, alert: "Rate limit: max 2 syncs per day per account. Try again tomorrow."
      return
    end
    SyncExchangeAccountJob.perform_later(@exchange_account.id)
    redirect_to exchange_accounts_path, notice: "Sync started. Trades will appear shortly."
  end

  private

  def set_exchange_account
    @exchange_account = current_user.exchange_accounts.find(params[:id])
  end

  def exchange_account_params
    params.require(:exchange_account).permit(:provider_type, :api_key, :api_secret)
  end
end
