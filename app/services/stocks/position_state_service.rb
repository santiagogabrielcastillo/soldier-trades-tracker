# frozen_string_literal: true

module Stocks
  # Builds per-ticker position state from stock_trades: shares held, net USD invested,
  # breakeven price, realized PnL (FIFO). Unrealized PnL is computed in the view using current price.
  class PositionStateService
    PositionSummary = Struct.new(
      :ticker,
      :shares,
      :net_usd_invested,
      :breakeven,
      :realized_pnl,
      :open?,
      :opened_at,
      :closed_at,
      keyword_init: true
    )

    def self.call(stock_portfolio:)
      new(stock_portfolio: stock_portfolio).call
    end

    def initialize(stock_portfolio:)
      @stock_portfolio = stock_portfolio
    end

    def call
      trades = @stock_portfolio.stock_trades.ordered_by_executed_at.to_a
      return [] if trades.empty?

      by_ticker = trades.group_by(&:ticker)
      summaries = by_ticker.flat_map { |ticker, txs| build_summaries_for_ticker(ticker, txs) }
      summaries.sort_by! { |s| [ s.open? ? 0 : 1, -(s.closed_at || s.opened_at || Time.at(0)).to_i ] }
    end

    private

    def build_summaries_for_ticker(ticker, trades)
      txs = trades.sort_by { |t| [ t.executed_at, t.id ] }
      summaries = []
      shares = BigDecimal("0")
      net_usd = BigDecimal("0")
      realized_pnl = BigDecimal("0")
      lots = [] # FIFO: [ [qty, cost_per_share], ... ]
      epoch_start = nil

      txs.each do |tx|
        if tx.side == "buy"
          if shares.zero?
            epoch_start = tx.executed_at
            net_usd = BigDecimal("0")
            realized_pnl = BigDecimal("0")
            lots = []
          end
          shares += tx.shares.to_d
          net_usd += tx.total_value_usd.to_d
          lots << [ tx.shares.to_d, tx.price_usd.to_d ]
        else
          # sell — reduce net_usd by the FIFO cost of the shares sold, not the proceeds
          remaining_sell = tx.shares.to_d
          sell_price = tx.price_usd.to_d
          cost_of_sold = BigDecimal("0")
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
            cost_of_sold  += consumed * cost
          end
          net_usd -= cost_of_sold
          shares  -= tx.shares.to_d
          if shares <= 0
            summaries << PositionSummary.new(
              ticker: ticker,
              shares: BigDecimal("0"),
              net_usd_invested: net_usd,
              breakeven: nil,
              realized_pnl: realized_pnl,
              open?: false,
              opened_at: epoch_start,
              closed_at: tx.executed_at
            )
            shares = BigDecimal("0")
          end
        end
      end

      if shares.positive?
        breakeven = (net_usd / shares).round(8)
        summaries << PositionSummary.new(
          ticker: ticker,
          shares: shares,
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
