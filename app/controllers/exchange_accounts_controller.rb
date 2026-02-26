# frozen_string_literal: true

class ExchangeAccountsController < ApplicationController
  before_action :set_exchange_account, only: :destroy

  def index
    @exchange_accounts = current_user.exchange_accounts
  end

  def new
    @exchange_account = current_user.exchange_accounts.build
  end

  def create
    @exchange_account = current_user.exchange_accounts.build(exchange_account_params)
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

  private

  def set_exchange_account
    @exchange_account = current_user.exchange_accounts.find(params[:id])
  end

  def exchange_account_params
    params.require(:exchange_account).permit(:provider_type, :api_key, :api_secret)
  end
end
