# frozen_string_literal: true

class SyncExchangeAccountJob < ApplicationJob
  queue_as :default

  retry_on Exchanges::ApiError, wait: :polynomially_longer, attempts: 5

  # Rate limit: caller (dispatcher) must ensure this account has fewer than 2 sync runs today (UTC).
  def perform(exchange_account_id, historic: false)
    account = ExchangeAccount.find_by(id: exchange_account_id)
    return unless account

    ExchangeAccounts::SyncService.call(account, historic: historic)
    account.update_columns(last_sync_failed_at: nil, last_sync_error: nil)
  rescue ArgumentError => e
    Rails.logger.error("[SyncExchangeAccountJob] account_id=#{exchange_account_id} #{e.message}")
  rescue => e
    Rails.logger.error("[SyncExchangeAccountJob] account_id=#{exchange_account_id} error=#{e.message}")
    account = ExchangeAccount.find_by(id: exchange_account_id)
    account&.update_columns(last_sync_failed_at: Time.current.utc, last_sync_error: e.message.truncate(500))
    raise
  end
end
