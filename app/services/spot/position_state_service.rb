# frozen_string_literal: true

module Spot
  # Builds per-token position state from spot_transactions: balance, epochs, net USD invested,
  # breakeven, realized PnL (FIFO). Unrealized PnL is computed in the view using current price.
  class PositionStateService
    PositionSummary = Struct.new(
      :token,
      :balance,
      :net_usd_invested,
      :breakeven,
      :realized_pnl,
      :open?,
      :opened_at,
      :closed_at,
      keyword_init: true
    ) do
      def risk_free?
        net_usd_invested.to_d < 0
      end
    end

    def self.call(spot_account:)
      new(spot_account: spot_account).call
    end

    def initialize(spot_account:)
      @spot_account = spot_account
    end

    def call
      transactions = @spot_account.spot_transactions.trades.ordered_by_executed_at.to_a
      return [] if transactions.empty?

      by_token = transactions.group_by(&:token)
      summaries = by_token.flat_map { |token, txs| build_summaries_for_token(token, txs) }
      # Open first, then closed by closed_at desc
      summaries.sort_by! { |s| [ s.open? ? 0 : 1, -(s.closed_at || s.opened_at || Time.at(0)).to_i ] }
    end

    private

    def build_summaries_for_token(token, transactions)
      txs = transactions.sort_by { |t| [ t.executed_at, t.id ] }
      summaries = []
      balance = BigDecimal("0")
      net_usd = BigDecimal("0")
      realized_pnl = BigDecimal("0")
      lots = [] # FIFO: [ [qty, price_usd], ... ]
      epoch_start = nil

      txs.each do |tx|
        if tx.side == "buy"
          if balance.zero?
            epoch_start = tx.executed_at
            net_usd = BigDecimal("0")
            realized_pnl = BigDecimal("0")
            lots = []
          end
          balance += tx.amount
          net_usd += tx.total_value_usd.to_d
          lots << [ tx.amount.to_d, tx.price_usd.to_d ]
        else
          # sell
          remaining_sell = tx.amount.to_d
          sell_price = tx.price_usd.to_d
          while remaining_sell > 0 && lots.any?
            qty, cost = lots.first
            if remaining_sell >= qty
              lots.shift
              consumed = qty
            else
              lots[0] = [ qty - remaining_sell, cost ]
              consumed = remaining_sell
            end
            remaining_sell -= consumed
            realized_pnl += consumed * (sell_price - cost)
          end
          net_usd -= (tx.amount.to_d * sell_price)
          balance -= tx.amount.to_d
          if balance.zero?
            summaries << PositionSummary.new(
              token: token,
              balance: BigDecimal("0"),
              net_usd_invested: net_usd,
              breakeven: nil,
              realized_pnl: realized_pnl,
              open?: false,
              opened_at: epoch_start,
              closed_at: tx.executed_at
            )
          end
        end
      end

      if balance.positive?
        breakeven = (net_usd / balance).round(8)
        breakeven = BigDecimal("0") if breakeven.negative? # risk-free
        summaries << PositionSummary.new(
          token: token,
          balance: balance,
          net_usd_invested: net_usd,
          breakeven: breakeven,
          realized_pnl: realized_pnl,
          open?: true,
          opened_at: epoch_start,
          closed_at: nil
        )
      end

      summaries
    end
  end
end
