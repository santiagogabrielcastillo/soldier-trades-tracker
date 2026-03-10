# frozen_string_literal: true

# Rebuilds Position and PositionTrade rows for an exchange account from its Trade records.
# Uses the same grouping/BOTH-chain logic as PositionSummary. Call after sync.
module Positions
  class RebuildForAccountService
    def self.call(account)
      new(account).call
    end

    def initialize(account)
      @account = account
    end

    def call
      trades = @account.trades.includes(:exchange_account).order(executed_at: :asc).limit(PositionSummary::TRADES_LIMIT)
      return :ok if trades.empty?

      leverage_by_symbol = Positions::CurrentDataFetcher.leverage_by_symbol(trades)
      summaries = PositionSummary.from_trades(trades, leverage_by_symbol: leverage_by_symbol)

      Position.transaction do
        @account.positions.destroy_all
        summaries.each { |s| persist_summary(s) }
      end
      :ok
    end

    private

    def persist_summary(summary)
      pos = Position.create!(
        exchange_account_id: summary.exchange_account.id,
        symbol: summary.symbol,
        position_side: summary.position_side,
        leverage: summary.leverage,
        open_at: summary.open_at,
        close_at: summary.close_at,
        margin_used: summary.margin_used,
        net_pl: summary.net_pl,
        entry_price: summary.entry_price,
        exit_price: summary.exit_price,
        open_quantity: summary.open_quantity,
        closed_quantity: summary.closed_quantity,
        total_commission: summary.total_commission,
        open: summary.open?,
        excess_from_over_close: summary.excess_from_over_close == true
      )
      summary.trades.each { |t| PositionTrade.create!(position: pos, trade: t) }
    end
  end
end
