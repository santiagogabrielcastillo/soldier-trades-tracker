# frozen_string_literal: true

# One row for the trades index: one per closing leg (each take-profit/stop closes one row), so margin and ROI match the exchange.
# Single-fill positions (no position_id or one trade) get one row. Built by grouping Trade by position_id.
class PositionSummary
  # Max trades to load when building summaries (used by Trades::IndexService and Dashboards::SummaryService).
  TRADES_LIMIT = 2000

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

  # Build position summaries from trades and assign running balance.
  # Optional initial_balance is the portfolio starting balance; defaults to 0 for all-time view.
  # Returns array of PositionSummary sorted by close_at desc, with #balance set.
  def self.from_trades_with_balance(trades, initial_balance: nil)
    positions = from_trades(trades)
    assign_balance!(positions, initial_balance: initial_balance.to_d)
    positions
  end

  # Build position summaries from a list of trades (e.g. current_user.trades).
  # One row per closing leg (matches BingX per take-profit), or one row for single-fill positions.
  # Returns array of PositionSummary sorted by close_at desc.
  def self.from_trades(trades)
    list = trades.to_a
    return [] if list.empty?

    by_position = list.group_by { |t| t.position_id.presence || "single_#{t.exchange_reference_id}" }

    summaries = by_position.flat_map do |_key, position_trades|
      build_summaries(position_trades)
    end

    # Sort by close_at desc (newest first)
    summaries.sort_by! { |s| s.close_at || Time.at(0) }
    summaries.reverse!
  end

  # One row per closing leg so margin/ROI match exchange (e.g. BingX). Single-fill => one row.
  def self.build_summaries(position_trades)
    trades = position_trades.sort_by(&:executed_at)
    open_trade = trades.first
    closing = trades.select { |t| closing_leg?(t, open_trade) }

    if closing.empty?
      # Single-fill position or no close yet: one row using whole position
      return [build_one_aggregate(trades)]
    end

    # One row per closing trade (each take-profit/stop)
    leverage = open_trade.leverage_from_raw
    closing.map do |close_trade|
      build_one_leg(open_trade, close_trade, leverage)
    end
  end

  # BingX ROI = profit / (opening_margin * closed_qty / open_qty), not closing notional/leverage.
  def self.build_one_leg(open_trade, close_trade, leverage)
    open_notional = open_trade.notional_from_raw
    open_margin = (leverage && leverage.positive? && open_notional.positive?) ? (open_notional / leverage).round(8) : nil
    open_qty = (open_trade.raw_payload || {})["executedQty"].to_s.presence || (open_trade.raw_payload || {})["executed_qty"].to_s.presence || (open_trade.raw_payload || {})["origQty"].to_s.presence
    open_qty = open_qty.to_d
    close_qty = (close_trade.raw_payload || {})["executedQty"].to_s.presence || (close_trade.raw_payload || {})["executed_qty"].to_s.presence || (close_trade.raw_payload || {})["origQty"].to_s.presence
    close_qty = close_qty.to_d
    margin_used = if open_margin && open_qty.positive?
      (open_margin * (close_qty / open_qty)).round(8)
    end
    profit = close_trade.realized_profit_from_raw
    net_pl = profit.nil? ? close_trade.net_amount : profit

    new(
      trades: [open_trade, close_trade],
      exchange_account: open_trade.exchange_account,
      symbol: open_trade.symbol,
      leverage: leverage,
      open_at: open_trade.executed_at,
      close_at: close_trade.executed_at,
      margin_used: margin_used,
      net_pl: net_pl
    )
  end

  def self.build_one_aggregate(position_trades)
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

  # Commission for this row. One-row-per-close: only this leg's fee; aggregate/single-fill: sum of fees.
  # Returns a negative number (cost). Use .abs for display as "you paid $X.XX".
  def total_commission
    if trades.size == 2 && self.class.closing_leg?(trades.last, trades.first)
      trades.last.fee.to_d
    else
      trades.sum { |t| t.fee.to_d }
    end
  end

  # ROI = (net_pl / effective_margin) * 100. For partial closes, effective_margin is proportional to closed
  # quantity (margin_used * closed_qty / open_qty) so ROI reflects return on the capital that was actually released.
  def roi_percent
    return nil if margin_used.blank? || margin_used.zero?
    effective = effective_margin_for_roi
    return nil if effective.blank? || effective.zero?
    (net_pl / effective * 100).round(2)
  end

  # Margin that actually generated the realized P&L. For one-row-per-close we already store margin for this leg => margin_used.
  def effective_margin_for_roi
    return nil if margin_used.blank?
    # One row per closing leg: margin_used is already this leg's margin.
    return margin_used if trades.size == 2 && self.class.closing_leg?(trades.last, trades.first)
    open_qty = open_quantity
    closed_qty = closed_quantity
    return nil if open_qty.blank? || open_qty.zero?
    return margin_used if trades.size <= 1
    return nil if closed_qty.blank? || closed_qty.zero?
    ratio = (closed_qty / open_qty).to_d
    (margin_used * ratio).round(8)
  end

  def open_quantity
    first = trades.first
    return nil unless first
    raw = first.raw_payload || {}
    (raw["executedQty"] || raw["executed_qty"] || raw["origQty"] || 0).to_d
  end

  def closed_quantity
    closing = trades.select { |t| closing_leg?(t) }
    return 0.to_d if closing.empty?
    closing.sum do |t|
      raw = t.raw_payload || {}
      (raw["executedQty"] || raw["executed_qty"] || raw["origQty"] || 0).to_d
    end
  end

  # Position direction from the opening trade: "long" (opened with BUY) or "short" (opened with SELL).
  # Uses raw positionSide if present (e.g. BingX), else infers from side.
  def position_side
    first = trades.first
    return nil unless first
    raw = first.raw_payload || {}
    ps = (raw["positionSide"] || raw["position_side"]).to_s.strip.upcase
    return "long" if ps == "LONG"
    return "short" if ps == "SHORT"
    side = (first.side || raw["side"]).to_s.strip.upcase
    return "long" if side == "BUY"
    return "short" if side == "SELL"
    nil
  end

  def self.closing_leg?(trade, open_trade)
    raw = trade.raw_payload || {}
    return true if raw["reduceOnly"] == true || raw["reduceOnly"].to_s == "true"
    open_side = (open_trade.raw_payload || {})["side"].to_s.upcase
    trade_side = raw["side"].to_s.upcase
    return false if open_side.blank? || trade_side.blank?
    (open_side == "SELL" && trade_side == "BUY") || (open_side == "BUY" && trade_side == "SELL")
  end

  def closing_leg?(trade)
    return false if trades.empty?
    self.class.closing_leg?(trade, trades.first)
  end

  # True when this row has no closing leg (open position). Used for display and unrealized PnL/ROI.
  def open?
    trades.none? { |t| closing_leg?(t) }
  end

  # Entry price from the opening trade. Used for unrealized PnL. Returns nil if not available.
  def entry_price
    first = trades.first
    return nil unless first
    raw = first.raw_payload || {}
    avg = raw["avgPrice"] || raw["avg_price"]
    return avg.to_d if avg.present? && avg.to_s.to_d.nonzero?
    qty = open_quantity
    return nil if qty.blank? || qty.zero?
    notional = first.notional_from_raw
    return nil unless notional.present? && notional.positive?
    (notional / qty).round(8)
  end

  # Unrealized PnL at current_price (quote/USDT). Long: (current - entry) * qty; short: (entry - current) * qty.
  # Returns nil when open? is false, current_price is blank, or entry_price/qty is missing.
  def unrealized_pnl(current_price)
    return nil unless open?
    return nil if current_price.blank?
    price = current_price.to_d
    entry = entry_price
    return nil if entry.blank? || entry.zero?
    qty = open_quantity
    return nil if qty.blank? || qty.zero?
    diff = case position_side
    when "long" then (price - entry) * qty
    when "short" then (entry - price) * qty
    else nil
    end
    diff&.round(8)
  end

  # Unrealized ROI percent: (unrealized_pnl / margin_used) * 100. Returns nil when not open or data missing.
  def unrealized_roi_percent(current_price)
    return nil unless open?
    return nil if margin_used.blank? || margin_used.zero?
    pl = unrealized_pnl(current_price)
    return nil if pl.nil?
    (pl / margin_used * 100).round(2)
  end

  # Assign running balance (newest first): balance at row i = initial_balance + cumulative net_pl for that row and all rows below it.
  def self.assign_balance!(summaries, initial_balance: 0)
    base = initial_balance.to_d
    total = summaries.sum(&:net_pl)
    summaries.each do |s|
      s.balance = base + total
      total -= s.net_pl
    end
  end
end
