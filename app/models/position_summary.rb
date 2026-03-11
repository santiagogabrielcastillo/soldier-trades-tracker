# frozen_string_literal: true

# One row per position for the trades index: open-only => one row; closed => one aggregated row (all closing legs combined).
# Single-fill positions (no position_id or one trade) get one row. Built by grouping Trade by position_id (with BOTH chain splitting).
class PositionSummary
  # Max trades to load when building summaries (used by Trades::IndexService and Dashboards::SummaryService).
  TRADES_LIMIT = 2000

  attr_reader :trades, :exchange_account, :symbol, :leverage, :open_at, :close_at, :net_pl
  attr_accessor :balance, :remaining_quantity, :remaining_margin_used, :excess_from_over_close

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
  # leverage_by_symbol: optional Hash[app_symbol => Integer] (e.g. from Binance positionRisk) when trades don't have leverage in raw.
  # Returns array of PositionSummary sorted open first then closed by date, with #balance set.
  def self.from_trades_with_balance(trades, initial_balance: nil, leverage_by_symbol: nil)
    positions = from_trades(trades, leverage_by_symbol: leverage_by_symbol)
    assign_balance!(positions, initial_balance: initial_balance.to_d)
    positions
  end

  # Build position summaries from a list of trades (e.g. current_user.trades).
  # One row per position (closed positions = one aggregated row), or one row for single-fill/open-only.
  # When position_id is "BOTH" (Binance one-way mode), we split by position chains: each time
  # running quantity crosses zero we start a new chain so one open + its closes form one group.
  # leverage_by_symbol: optional Hash[app_symbol => Integer] for providers (e.g. Binance) that don't return leverage per trade.
  # Returns array of PositionSummary sorted: open positions first, then closed by close_at desc.
  def self.from_trades(trades, leverage_by_symbol: nil)
    list = trades.to_a
    return [] if list.empty?

    # Group by symbol first so BOTH chain-splitting runs per symbol (Binance has position_id BOTH for all).
    position_groups = list.group_by(&:symbol).flat_map do |_symbol, symbol_trades|
      by_position = symbol_trades.group_by { |t| t.position_id.presence || "single_#{t.exchange_reference_id}" }
      by_position.flat_map do |key, position_trades|
        if key.to_s.upcase == "BOTH"
          split_both_chains(position_trades).map { |chain| [ nil, chain, true ] }
        else
          [ [ key, position_trades, false ] ]
        end
      end
    end

    summaries = position_groups.flat_map do |_key, position_trades, from_both_chain|
      build_summaries(position_trades, leverage_by_symbol: leverage_by_symbol, from_both_chain: from_both_chain)
    end.compact

    # Open first (0), then closed (1); within each group by most recent activity desc
    recent_at = ->(s) { (s.close_at || s.open_at || Time.at(0)).to_i }
    summaries.sort_by! { |s| [ s.open? ? 0 : 1, -recent_at.call(s) ] }
  end

  # One row per position: open-only => one row; closed (one or many legs) => one aggregated row (+ remainder if partial).
  # Supports multiple opening trades (same side) per chain, e.g. Binance one-way add-to-position.
  # leverage_by_symbol: optional Hash[app_symbol => Integer] for providers that don't return leverage per trade (e.g. Binance).
  def self.build_summaries(position_trades, leverage_by_symbol: nil, from_both_chain: false)
    trades = position_trades.sort_by(&:executed_at)
    if from_both_chain
      first = trades.first
      open_trades = trades.take_while { |t| same_side?(t, first) }
      closing = trades - open_trades
    else
      open_trades = trades.reject { |t| reduce_only?(t) }.sort_by(&:executed_at)
      closing = trades.select { |t| reduce_only?(t) }.sort_by(&:executed_at)
    end
    return [] if open_trades.empty?

    first = open_trades.first
    leverage = first.leverage_from_raw
    if leverage.blank? && leverage_by_symbol.present? && first.symbol.present?
      n = leverage_by_symbol[first.symbol].to_i
      leverage = n.positive? ? n : nil
    end

    if closing.empty?
      # Single-fill position or no close yet: one row using whole position
      return [ build_one_aggregate(trades, leverage: leverage) ]
    end

    # One row per closing leg (so each partial close shows its own margin and ROI). Plus remainder row if partial close.
    open_notional = open_trades.sum { |t| t.notional_from_raw.to_d }
    open_margin = (leverage && leverage.positive? && open_notional.positive?) ? (open_notional / leverage).round(8) : nil
    open_qty = open_trades.sum(BigDecimal("0")) do |t|
      raw = t.raw_payload || {}
      (raw["executedQty"] || raw["executed_qty"] || raw["origQty"] || raw["qty"] || 0).to_d
    end
    total_closed_qty = closing.sum(BigDecimal("0")) do |close_trade|
      raw = close_trade.raw_payload || {}
      (raw["executedQty"] || raw["executed_qty"] || raw["origQty"] || raw["qty"] || 0).to_d
    end

    closed_rows = closing.sort_by(&:executed_at).filter_map { |close_trade| build_one_leg(open_trades, close_trade, leverage) }
    rows = closed_rows

    if open_margin && open_qty.positive? && total_closed_qty < open_qty
      remaining_qty = (open_qty - total_closed_qty).round(8)
      remainder_margin = (open_margin * (remaining_qty / open_qty)).round(8)
      last_trade = trades.last
      remainder = new(
        trades: open_trades,
        exchange_account: first.exchange_account,
        symbol: first.symbol,
        leverage: leverage,
        open_at: first.executed_at,
        close_at: last_trade.executed_at,
        margin_used: remainder_margin,
        net_pl: 0
      )
      remainder.remaining_quantity = remaining_qty
      remainder.remaining_margin_used = remainder_margin
      rows << remainder
    elsif total_closed_qty > open_qty
      # Over-close: excess closed qty opened a new position in the opposite direction. Emit one open row for it.
      excess_qty = (total_closed_qty - open_qty).round(8)
      first_close = closing.first
      entry = entry_price_from_trade(first_close)
      excess_margin = if leverage.present? && leverage.positive? && entry.present? && entry.positive?
        (excess_qty * entry / leverage).round(8)
      else
        nil
      end
      excess_row = new(
        trades: [ first_close ],
        exchange_account: first_close.exchange_account,
        symbol: first_close.symbol,
        leverage: leverage,
        open_at: first_close.executed_at,
        close_at: first_close.executed_at,
        margin_used: excess_margin,
        net_pl: 0
      )
      excess_row.remaining_quantity = excess_qty
      excess_row.remaining_margin_used = excess_margin
      excess_row.excess_from_over_close = true
      rows << excess_row
    end
    rows
  end

  # One row for a fully or partially closed position: all closing legs aggregated (total PnL, last close_at).
  # Use exchange-reported realized PnL only; do not use net_amount (cash flow) for closes.
  def self.build_one_aggregate_closed(open_trades, closing_trades, leverage, open_margin)
    open_trades = Array(open_trades).compact
    first_open = open_trades.first
    return nil if first_open.nil?
    last_close = closing_trades.max_by(&:executed_at)
    net_pl = closing_trades.sum(BigDecimal("0")) do |t|
      (t.realized_profit_from_raw || 0).to_d
    end
    new(
      trades: open_trades + closing_trades,
      exchange_account: first_open.exchange_account,
      symbol: first_open.symbol,
      leverage: leverage,
      open_at: first_open.executed_at,
      close_at: last_close.executed_at,
      margin_used: open_margin,
      net_pl: net_pl
    )
  end

  # BingX ROI = profit / (opening_margin * closed_qty / open_qty), not closing notional/leverage.
  # open_trades: one or more opening trades (same side) for this position.
  def self.build_one_leg(open_trades, close_trade, leverage)
    open_trades = Array(open_trades).compact
    first_open = open_trades.first
    return nil if first_open.nil?
    open_notional = open_trades.sum { |t| t.notional_from_raw.to_d }
    open_margin = (leverage && leverage.positive? && open_notional.positive?) ? (open_notional / leverage).round(8) : nil
    open_qty = open_trades.sum(BigDecimal("0")) do |t|
      raw = t.raw_payload || {}
      (raw["executedQty"] || raw["executed_qty"] || raw["origQty"] || raw["qty"] || 0).to_d
    end
    close_raw = close_trade.raw_payload || {}
    close_qty = (close_raw["executedQty"] || close_raw["executed_qty"] || close_raw["origQty"] || close_raw["qty"]).to_s.presence&.then { |v| v.to_d } || 0.to_d
    margin_used = if open_margin && open_qty.positive?
      (open_margin * (close_qty / open_qty)).round(8)
    end
    profit = close_trade.realized_profit_from_raw
    net_pl = profit.nil? ? close_trade.net_amount : profit

    new(
      trades: open_trades + [ close_trade ],
      exchange_account: first_open.exchange_account,
      symbol: first_open.symbol,
      leverage: leverage,
      open_at: first_open.executed_at,
      close_at: close_trade.executed_at,
      margin_used: margin_used,
      net_pl: net_pl
    )
  end

  # Open-only position (no closing legs): realized PnL is 0. Do not use net_amount (opening cost) as PnL.
  # leverage: optional override (e.g. from Binance positionRisk when trade raw has no leverage).
  def self.build_one_aggregate(position_trades, leverage: nil)
    trades = position_trades.sort_by(&:executed_at)
    first = trades.first
    last = trades.last
    account = first.exchange_account
    symbol = first.symbol
    leverage = leverage || first.leverage_from_raw
    notional = trades.sum { |t| t.notional_from_raw.to_d }
    margin_used = if leverage && leverage.positive? && notional.positive?
      (notional / leverage).round(8)
    end
    # Open position has no realized PnL; never show opening cost (net_amount) as P&L
    net_pl = 0

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
  # Remainder (remaining open) row reports 0 so we don't show open-trade fee on the "Open" row.
  # Returns a negative number (cost). Use .abs for display as "you paid $X.XX".
  def total_commission
    return 0.to_d if @remaining_quantity.present?
    closing = trades.select { |t| closing_leg?(t) }
    if closing.size == 1
      closing.first.fee.to_d
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
    # One row per closing leg: margin_used is already this leg's margin (from build_one_leg).
    closing_legs = trades.select { |t| closing_leg?(t) }
    return margin_used if closing_legs.size == 1
    open_qty = open_quantity
    closed_qty = closed_quantity
    return nil if open_qty.blank? || open_qty.zero?
    return margin_used if trades.size <= 1
    return nil if closed_qty.blank? || closed_qty.zero?
    ratio = (closed_qty / open_qty).to_d
    (margin_used * ratio).round(8)
  end

  def margin_used
    @remaining_margin_used.presence || @margin_used
  end

  def open_quantity
    return @remaining_quantity if @remaining_quantity.present?
    opening = trades.reject { |t| closing_leg?(t) }
    return nil if opening.empty?
    opening.sum do |t|
      raw = t.raw_payload || {}
      (raw["executedQty"] || raw["executed_qty"] || raw["origQty"] || raw["qty"] || 0).to_d
    end
  end

  def closed_quantity
    closing = trades.select { |t| closing_leg?(t) }
    return 0.to_d if closing.empty?
    closing.sum do |t|
      raw = t.raw_payload || {}
      (raw["executedQty"] || raw["executed_qty"] || raw["origQty"] || raw["qty"] || 0).to_d
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

  # True when the trade is a reduce-only (closing) fill. Used to partition opening vs closing trades per position_id.
  def self.reduce_only?(trade)
    raw = trade.raw_payload || {}
    raw["reduceOnly"] == true || raw["reduceOnly"].to_s == "true" || raw["reduce_only"] == true || raw["reduce_only"].to_s == "true"
  end

  def self.closing_leg?(trade, open_trade)
    raw = trade.raw_payload || {}
    return true if reduce_only?(trade)
    open_side = (open_trade.raw_payload || {})["side"].to_s.upcase
    trade_side = raw["side"].to_s.upcase
    return false if open_side.blank? || trade_side.blank?
    (open_side == "SELL" && trade_side == "BUY") || (open_side == "BUY" && trade_side == "SELL")
  end

  # Same position direction: both BUY or both SELL. Used to group opening fills (e.g. Binance one-way can have reduceOnly on opening SELL).
  def self.same_side?(trade, open_trade)
    open_side = (open_trade.raw_payload || {})["side"].to_s.upcase
    trade_side = (trade.raw_payload || {})["side"].to_s.upcase
    return false if open_side.blank? || trade_side.blank?
    open_side == trade_side
  end

  def closing_leg?(trade)
    return false if trades.empty?
    self.class.closing_leg?(trade, trades.first)
  end

  # True when this row has no closing leg (open position). Used for display and unrealized PnL/ROI.
  # Excess-from-over-close rows (one trade that closed the prior position and opened the opposite) count as open.
  def open?
    return true if excess_from_over_close
    trades.none? { |t| closing_leg?(t) }
  end

  # Exit price from the closing trade(s). Returns nil when open? or when no price available.
  # For aggregated close we use last closing trade. Binance: price or quoteQty/qty.
  def exit_price
    return nil if open?
    closing = trades.select { |t| closing_leg?(t) }
    return nil if closing.empty?
    close_trade = closing.max_by(&:executed_at)
    raw = close_trade.raw_payload || {}
    avg = raw["avgPrice"] || raw["avg_price"] || raw["price"]
    return avg.to_d if avg.present? && avg.to_s.to_d.nonzero?
    qq = (raw["quoteQty"] || raw["quote_qty"] || 0).to_d
    q = (raw["qty"] || raw["executedQty"] || raw["executed_qty"] || 0).to_d
    return (qq / q).round(8) if q.positive? && qq.positive?
    qty = closed_quantity
    return nil if qty.blank? || qty.zero?
    notional = close_trade.notional_from_raw
    return nil unless notional.present? && notional.positive?
    (notional / qty).round(8)
  end

  # Entry price from the opening trade(s). Used for unrealized PnL. VWAP when multiple opens.
  # Binance: raw["price"] or raw["quoteQty"]/raw["qty"]; BingX: avgPrice, avg_price.
  # For excess-from-over-close rows, the single trade is the fill that opened the position; use its price.
  def entry_price
    if excess_from_over_close && trades.any?
      return self.class.entry_price_from_trade(trades.first)
    end
    opening = trades.reject { |t| closing_leg?(t) }
    return nil if opening.empty?
    first = opening.first
    if opening.size == 1
      raw = first.raw_payload || {}
      avg = raw["avgPrice"] || raw["avg_price"] || raw["price"]
      if avg.present? && avg.to_s.to_d.nonzero?
        return avg.to_d
      end
      # Binance userTrades: price may be in "price"; fallback quoteQty/qty
      qq = (raw["quoteQty"] || raw["quote_qty"] || 0).to_d
      q = (raw["qty"] || raw["executedQty"] || raw["executed_qty"] || 0).to_d
      return (qq / q).round(8) if q.positive? && qq.positive?
    end
    qty = open_quantity
    return nil if qty.blank? || qty.zero?
    total_notional = opening.sum { |t| t.notional_from_raw.to_d }
    return nil unless total_notional.positive?
    (total_notional / qty).round(8)
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

  # Binance one-way mode: positionSide is "BOTH" for every trade. Split into chains by running quantity.
  # When a trade would make running qty cross zero, that trade is the close that crosses — keep it in the
  # current chain, then start a new chain for the next trade (so we get e.g. [BUY, SELL] not [BUY] + [SELL]).
  def self.split_both_chains(position_trades)
    sorted = position_trades.sort_by(&:executed_at)
    chains = []
    current = []
    running = 0.to_d
    sorted.each do |t|
      signed = signed_quantity_for(t)
      crosses = (running.positive? && running + signed <= 0) || (running.negative? && running + signed >= 0)
      if crosses
        current << t
        running += signed
        chains << current if current.any?
        current = []
      else
        current << t
        running += signed
      end
    end
    chains << current if current.any?

    # Running ended at zero => last chain is the close of the previous, not a new position.
    if running.zero? && chains.size >= 2
      chains[-2].concat(chains.last)
      chains.pop
    end

    # First chain is a single trade with zero qty (e.g. BUY with qty missing in raw) => one position, merge all.
    if chains.size >= 2 && chains.first.size == 1 && signed_quantity_for(chains.first.first).zero?
      chains = [ chains.flatten ]
    end

    # Last chain is same-side-only (or single opposite) and first has opposite side. Merge only when the
    # combined running qty is zero (last chain is the tail of the same close). Do not merge when the last
    # chain is a new position in the opposite direction (e.g. Long closed then new Short open).
    while chains.size >= 2 && first_chain_has_opposite_side?(chains.first, chains.last) && (same_side_chain?(chains.last) || chains.last.size == 1)
      combined = chains[-2] + chains.last
      combined_running = combined.sum { |t| signed_quantity_for(t) }
      break unless combined_running.zero?
      chains[-2].concat(chains.pop)
    end

    chains
  end

  def self.same_side_chain?(chain)
    return true if chain.size <= 1
    first = chain.first
    chain.all? { |t| same_side?(t, first) }
  end

  def self.first_chain_has_opposite_side?(first_chain, last_chain)
    return false if last_chain.empty?
    last_side = (last_chain.first.raw_payload || {})["side"].to_s.upcase
    first_chain.any? do |t|
      side = (t.raw_payload || {})["side"].to_s.upcase
      (last_side == "BUY" && side == "SELL") || (last_side == "SELL" && side == "BUY")
    end
  end

  # Signed quantity for running balance: positive for BUY, negative for SELL.
  def self.signed_quantity_for(trade)
    raw = trade.raw_payload || {}
    qty = (raw["executedQty"] || raw["executed_qty"] || raw["origQty"] || raw["qty"] || 0).to_d
    return 0.to_d if qty.zero?
    side = raw["side"].to_s.upcase
    side == "SELL" ? -qty : qty
  end

  # Price from a single trade (Binance: price or quoteQty/qty). Used for over-close excess row entry.
  def self.entry_price_from_trade(trade)
    raw = trade.raw_payload || {}
    avg = raw["avgPrice"] || raw["avg_price"] || raw["price"]
    return avg.to_d if avg.present? && avg.to_s.to_d.nonzero?
    qq = (raw["quoteQty"] || raw["quote_qty"] || 0).to_d
    q = (raw["qty"] || raw["executedQty"] || raw["executed_qty"] || 0).to_d
    (q.positive? && qq.positive?) ? (qq / q).round(8) : nil
  end

  private_class_method :split_both_chains, :signed_quantity_for, :same_side_chain?, :first_chain_has_opposite_side?
end
