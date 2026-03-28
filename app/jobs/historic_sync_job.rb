# frozen_string_literal: true

# Triggered by an admin to fetch the full trade history for an exchange account
# from 2018-01-01 (exchange inception). Bypasses the regular 2-syncs/day rate limit.
# The next iteration will add the admin UI trigger; this job is the plumbing.
class HistoricSyncJob < ApplicationJob
  queue_as :default

  def perform(exchange_account_id)
    account = ExchangeAccount.find_by(id: exchange_account_id)
    return unless account

    account.update_column(:last_synced_at, nil)
    ExchangeAccounts::SyncService.call(account, historic: true)
    account.update_column(:historic_sync_requested_at, nil)
  rescue => e
    Rails.logger.error("[HistoricSyncJob] account_id=#{exchange_account_id} error=#{e.message}")
    ExchangeAccount.find_by(id: exchange_account_id)&.update_columns(
      last_sync_failed_at: Time.current.utc,
      last_sync_error: e.message.truncate(500)
    )
    raise
  end
end
