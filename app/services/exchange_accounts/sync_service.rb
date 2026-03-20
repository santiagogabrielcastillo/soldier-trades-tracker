# frozen_string_literal: true

class ExchangeAccounts::SyncService
  # Binance userTrades only returns last 6 months; use that for first sync so we get history.
  BINANCE_LOOKBACK = 6.months

  # Fetches trades from the account's provider, applies FinancialCalculator for trade-style
  # hashes, persists trades (rescues RecordNotUnique per row), rebuilds positions, then creates
  # SyncRun and updates last_synced_at. So last_synced_at only advances when positions are consistent.
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

    since = since_for_fetch(client)
    trades = client.fetch_my_trades(since: since)

    trades.each { |attrs| persist_trade(attrs) }

    Positions::RebuildForAccountService.call(@account)
    SyncRun.create!(exchange_account_id: @account.id, ran_at: Time.current.utc)
    @account.update_column(:last_synced_at, Time.current.utc)
    :ok
  end

  private

  # Binance: use 6-month lookback when we have no trades yet or no previous sync (first run).
  # Otherwise use last_synced_at for incremental sync; non-Binance uses anchor.
  def since_for_fetch(client)
    anchor = @account.linked_at || @account.created_at
    use_binance_lookback = client.is_a?(Exchanges::BinanceClient) && (@account.trades.empty? || @account.last_synced_at.blank?)
    if use_binance_lookback
      [ anchor, BINANCE_LOOKBACK.ago ].min
    elsif @account.last_synced_at.present?
      @account.last_synced_at
    else
      anchor
    end
  end

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

    # Same logical trade can come from different BingX endpoints (V1 vs V2 vs income) with different
    # exchange_reference_ids. If we already have a trade with same content, update it instead of creating a duplicate.
    #
    # IMPORTANT — Binance skips this content-match dedup entirely:
    # Binance always provides unique exchange_reference_ids per fill. The content-match below was designed
    # for BingX (which can return the same fill via multiple endpoints with different IDs). When applied to
    # Binance, the content-match would incorrectly treat two legitimate fills as duplicates when they
    # coincidentally shared the same symbol/executed_at/side/net_amount — most commonly seen with USDC fills
    # where an ETH-USDT and ETH-USDC close could yield the same net_amount at the same timestamp. This was
    # the root cause of Binance USDC (and occasionally USDT) trades appearing to vanish after sync (PR #26).
    if trade.new_record? && @account.provider_type != "binance"
      existing = @account.trades.find_by(
        symbol: attrs[:symbol],
        executed_at: attrs[:executed_at],
        side: attrs[:side],
        net_amount: attrs[:net_amount]
      )
      if existing
        existing.assign_attributes(
          symbol: attrs[:symbol],
          side: attrs[:side],
          fee: attrs[:fee],
          net_amount: attrs[:net_amount],
          executed_at: attrs[:executed_at],
          raw_payload: attrs[:raw_payload] || {},
          position_id: attrs[:position_id]
        )
        existing.save!
        return
      end
    end

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
