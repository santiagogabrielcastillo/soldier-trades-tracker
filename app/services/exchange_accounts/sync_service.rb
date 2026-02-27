# frozen_string_literal: true

class ExchangeAccounts::SyncService
  # Fetches trades from the account's provider, applies FinancialCalculator for trade-style
  # hashes, persists trades (rescues RecordNotUnique per row), creates SyncRun, updates last_synced_at.
  # Raises Exchanges::ApiError on API failure so the job can retry.
  def self.call(account)
    new(account).call
  end

  def initialize(account)
    @account = account
  end

  def call
    client = Exchanges::ProviderForAccount.new(@account).client
    raise ArgumentError, "Unsupported provider or missing credentials" unless client

    since = @account.linked_at || @account.created_at
    trades = client.fetch_my_trades(since: since)

    trades.each { |attrs| persist_trade(attrs) }

    SyncRun.create!(exchange_account_id: @account.id, ran_at: Time.current.utc)
    @account.update_column(:last_synced_at, Time.current.utc)
    :ok
  end

  private

  def persist_trade(attrs)
    if attrs.key?(:price) && attrs.key?(:quantity)
      computed = Exchanges::FinancialCalculator.compute(
        price: attrs[:price],
        quantity: attrs[:quantity],
        side: attrs[:side],
        fee_from_exchange: attrs[:fee_from_exchange]
      )
      attrs = attrs.merge(fee: computed[:fee], net_amount: computed[:net_amount])
    end

    trade = @account.trades.find_or_initialize_by(exchange_reference_id: attrs[:exchange_reference_id])
    trade.assign_attributes(
      symbol: attrs[:symbol],
      side: attrs[:side],
      fee: attrs[:fee],
      net_amount: attrs[:net_amount],
      executed_at: attrs[:executed_at],
      raw_payload: attrs[:raw_payload] || {},
      position_id: attrs[:position_id]
    )
    trade.save!
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.warn("[SyncService] duplicate trade skipped: exchange_reference_id=#{attrs[:exchange_reference_id]}")
  end
end
