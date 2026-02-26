# frozen_string_literal: true

# One row for the trades index: represents a closed position (or a single fill when position_id is blank).
# Built by grouping Trade by position_id; margin and leverage come from the opening leg.
class PositionSummary
  attr_reader :trades, :exchange_account, :symbol, :leverage, :open_at, :close_at, :margin_used, :net_pl
  attr_accessor :balance

  def initialize(trades:, exchange_account:, symbol:, leverage:, open_at:, close_at:, margin_used:, net_pl:)
    @trades = trades
    @exchange_account = exchange_account
    @symbol = symbol
    @leverage = leverage
    @open_at = open_at
    @close_at = close_at
    @margin_used = margin_used
    @net_pl = net_pl
    @balance = nil
  end

  # Build position summaries from a list of trades (e.g. current_user.trades).
  # Groups by position_id; positions with no position_id become one-row summaries.
  # Returns array of PositionSummary sorted by close_at desc.
  def self.from_trades(trades)
    list = trades.to_a
    return [] if list.empty?

    by_position = list.group_by { |t| t.position_id.presence || "single_#{t.exchange_reference_id}" }

    summaries = by_position.map do |_key, position_trades|
      build_one(position_trades)
    end

    # Sort by close_at desc (newest first)
    summaries.sort_by! { |s| s.close_at || Time.at(0) }
    summaries.reverse!
  end

  def self.build_one(position_trades)
    trades = position_trades.sort_by(&:executed_at)
    first = trades.first
    last = trades.last
    account = first.exchange_account
    symbol = first.symbol

    leverage = first.leverage_from_raw
    notional = first.notional_from_raw
    margin_used = if leverage && leverage.positive? && notional.positive?
      (notional / leverage).round(8)
    end

    # Use exchange-reported realized P&L when present (e.g. BingX "profit" on close); else sum net_amount (cash flow).
    profits = trades.map(&:realized_profit_from_raw)
    net_pl = if profits.all?(&:nil?)
      trades.sum(&:net_amount)
    else
      profits.map { |p| p || 0 }.sum
    end

    new(
      trades: trades,
      exchange_account: account,
      symbol: symbol,
      leverage: leverage,
      open_at: first.executed_at,
      close_at: last.executed_at,
      margin_used: margin_used,
      net_pl: net_pl
    )
  end

  # Assign running balance (newest first): balance at row i = cumulative net_pl for that row and all rows below it.
  def self.assign_balance!(summaries)
    total = summaries.sum(&:net_pl)
    summaries.each do |s|
      s.balance = total
      total -= s.net_pl
    end
  end
end
