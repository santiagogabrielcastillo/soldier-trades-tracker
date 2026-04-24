# frozen_string_literal: true

class ExchangeAccountsController < ApplicationController
  before_action :set_exchange_account, only: %i[destroy sync historic_sync edit update]

  def index
    @pagy, @exchange_accounts = pagy(:offset, current_user.exchange_accounts, limit: 25)
  end

  def new
    @exchange_account = current_user.exchange_accounts.build(provider_type: "bingx")
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
      if current_user.exchange_accounts.count == 1
        flash[:info] = t("flash.exchange_account_linked_first")
        redirect_to exchange_accounts_path
      else
        redirect_to exchange_accounts_path, notice: t("flash.exchange_account_linked")
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @exchange_account.update(settings_params)
      redirect_to exchange_accounts_path, notice: t("flash.exchange_account_settings_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @exchange_account.destroy
    redirect_to exchange_accounts_path, notice: t("flash.exchange_account_removed")
  end

  def sync
    unless Exchanges::ProviderForAccount.new(@exchange_account).supported?
      redirect_to exchange_accounts_path, alert: t("flash.exchange_not_supported")
      return
    end
    unless @exchange_account.can_sync?
      redirect_to exchange_accounts_path, alert: t("flash.sync_rate_limit")
      return
    end
    SyncExchangeAccountJob.perform_later(@exchange_account.id)
    redirect_to exchange_accounts_path, notice: t("flash.sync_started")
  end

  def historic_sync
    unless current_user.admin? || current_user.super_admin?
      redirect_to exchange_accounts_path, alert: t("flash.not_authorized")
      return
    end
    unless Exchanges::ProviderForAccount.new(@exchange_account).supported?
      redirect_to exchange_accounts_path, alert: t("flash.exchange_not_supported")
      return
    end
    extra_symbols = params[:extra_symbols].to_s.split(/[\s,]+/).map(&:strip).map(&:upcase).reject(&:blank?)
    SyncExchangeAccountJob.perform_later(@exchange_account.id, historic: true, extra_symbols: extra_symbols)
    redirect_to exchange_accounts_path, notice: t("flash.historic_sync_started")
  end

  private

  def set_exchange_account
    @exchange_account = current_user.exchange_accounts.find(params[:id])
  end

  def exchange_account_params
    params.require(:exchange_account).permit(:provider_type, :api_key, :api_secret)
  end

  def settings_params
    params.require(:exchange_account).permit(allowed_quote_currencies: [])
  end
end
