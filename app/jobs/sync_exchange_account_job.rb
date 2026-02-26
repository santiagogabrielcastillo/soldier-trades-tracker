# frozen_string_literal: true

class SyncExchangeAccountJob < ApplicationJob
  queue_as :default

  # Rate limit: caller (dispatcher) must ensure this account has fewer than 2 sync runs today (UTC).
  # Failed runs do not create a SyncRun record so they don't count toward the cap.
  def perform(exchange_account_id)
    account = ExchangeAccount.find_by(id: exchange_account_id)
    return unless account
    return unless account.provider_type == "bingx"

    client = Exchanges::BingxClient.new(api_key: account.api_key, api_secret: account.api_secret)
    since = account.linked_at || account.created_at

    trades = client.fetch_my_trades(since: since)

    trades.each do |attrs|
      trade = account.trades.find_or_initialize_by(exchange_reference_id: attrs[:exchange_reference_id])
      trade.assign_attributes(
        symbol: attrs[:symbol],
        side: attrs[:side],
        fee: attrs[:fee],
        net_amount: attrs[:net_amount],
        executed_at: attrs[:executed_at],
        raw_payload: attrs[:raw_payload] || {}
      )
      trade.save!
    end

    SyncRun.create!(exchange_account_id: account.id, ran_at: Time.current.utc)
    account.update_column(:last_synced_at, Time.current.utc)
  rescue => e
    Rails.logger.error("[SyncExchangeAccountJob] account_id=#{exchange_account_id} error=#{e.message}")
    raise
  end
end
