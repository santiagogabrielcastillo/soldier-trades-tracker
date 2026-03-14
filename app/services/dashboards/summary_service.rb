# frozen_string_literal: true

class Dashboards::SummaryService
  def self.call(user)
    new(user).call
  end

  def initialize(user)
    @user = user
  end

  def call
    @exchange_accounts = @user.exchange_accounts
    @default_portfolio = @user.default_portfolio

    base = if @default_portfolio
      portfolio_summary
    else
      all_time_summary
    end
    base.merge(spot_summary)
  end

  private

  def portfolio_summary
    initial = @default_portfolio.initial_balance.to_d
    positions = load_positions_for_portfolio_with_fallback(@default_portfolio, initial)
    balance = initial + positions.sum(&:net_pl)
    current_prices = Positions::CurrentDataFetcher.current_prices_for_open_positions(positions)
    summary_unrealized_pl = total_unrealized_pl(positions, current_prices)
    analytics = build_analytics(positions, initial)

    {
      exchange_accounts: @exchange_accounts,
      default_portfolio: @default_portfolio,
      summary_label: @default_portfolio.name,
      summary_date_range: @default_portfolio.date_range_label,
      summary_period_pl: positions.sum(&:net_pl),
      summary_balance: balance,
      summary_position_count: positions.size,
      summary_unrealized_pl: summary_unrealized_pl,
      summary_trades_path_params: { view: "portfolio", portfolio_id: @default_portfolio.id }
    }.merge(analytics)
  end

  def all_time_summary
    positions = load_positions_all_time_with_fallback
    current_prices = Positions::CurrentDataFetcher.current_prices_for_open_positions(positions)
    summary_unrealized_pl = total_unrealized_pl(positions, current_prices)
    analytics = build_analytics(positions, 0.to_d)

    {
      exchange_accounts: @exchange_accounts,
      default_portfolio: nil,
      summary_label: "All time",
      summary_date_range: nil,
      summary_period_pl: positions.sum(&:net_pl),
      summary_balance: positions.sum(&:net_pl),
      summary_position_count: positions.size,
      summary_unrealized_pl: summary_unrealized_pl,
      summary_trades_path_params: { view: "history" }
    }.merge(analytics)
  end

  def load_positions_for_portfolio_with_fallback(portfolio, initial_balance)
    relation = load_positions_for_portfolio(portfolio)
    positions = relation.ordered_for_display.includes(:exchange_account).to_a
    if positions.any?
      Position.assign_balance!(positions, initial_balance: initial_balance)
      return positions
    end
    trades = portfolio.trades_in_range.includes(:exchange_account).order(executed_at: :asc).limit(PositionSummary::TRADES_LIMIT)
    return [] if trades.empty?

    leverage_by_symbol = Positions::CurrentDataFetcher.leverage_by_symbol(trades)
    PositionSummary.from_trades_with_balance(trades, initial_balance: initial_balance, leverage_by_symbol: leverage_by_symbol)
  end

  def load_positions_all_time_with_fallback
    positions = Position.for_user(@user).ordered_for_display.includes(:exchange_account).to_a
    if positions.any?
      Position.assign_balance!(positions, initial_balance: 0)
      return positions
    end
    trades = @user.trades.includes(:exchange_account).order(executed_at: :asc).limit(PositionSummary::TRADES_LIMIT)
    return [] if trades.empty?

    leverage_by_symbol = Positions::CurrentDataFetcher.leverage_by_symbol(trades)
    PositionSummary.from_trades_with_balance(trades, leverage_by_symbol: leverage_by_symbol)
  end

  def load_positions_for_portfolio(portfolio)
    base = if portfolio.exchange_account_id.present?
      Position.for_exchange_account(portfolio.exchange_account_id)
    else
      Position.for_user(@user)
    end
    base.in_date_range(portfolio.start_date, portfolio.end_date)
  end

  def build_analytics(positions, initial_balance)
    # Closed = any row that is not open (one row per position, possibly aggregated from multiple legs)
    closed = positions.reject(&:open?)
    closed_sorted = closed.sort_by { |s| s.close_at || Time.at(0) }

    total_return_pct = if initial_balance.present? && initial_balance.positive?
      balance = initial_balance + positions.sum(&:net_pl)
      ((balance - initial_balance) / initial_balance * 100).round(2)
    end

    winners = closed.select { |s| s.net_pl.positive? }
    losers = closed.select { |s| s.net_pl.negative? }
    win_rate = closed.empty? ? nil : (winners.size.to_d / closed.size * 100).round(2)
    avg_win = winners.any? ? (winners.sum(&:net_pl) / winners.size).round(8) : nil
    avg_loss = losers.any? ? (losers.sum(&:net_pl) / losers.size).round(8) : nil

    date_label = ->(t) { (t || Time.current).to_date.strftime("%b %d, %Y") }
    balance_series = closed_sorted.map { |s| { date: date_label.call(s.close_at), value: s.balance.to_f } }
    cumulative_pl_series = if initial_balance.present? && initial_balance.positive?
      closed_sorted.map { |s| { date: date_label.call(s.close_at), value: (s.balance - initial_balance).to_f } }
    else
      cum = 0.to_d
      closed_sorted.map { |s| cum += s.net_pl; { date: date_label.call(s.close_at), value: cum.to_f } }
    end

    {
      summary_total_return_pct: total_return_pct,
      summary_win_rate: win_rate,
      summary_avg_win: avg_win,
      summary_avg_loss: avg_loss,
      summary_closed_count: closed.size,
      chart_balance_series: balance_series,
      chart_cumulative_pl_series: cumulative_pl_series
    }
  end

  def total_unrealized_pl(positions, current_prices)
    open_positions = positions.select(&:open?)
    return 0.to_d if open_positions.empty?
    open_positions.sum(BigDecimal("0")) { |p| (p.unrealized_pnl(current_prices[p.symbol]) || 0).to_d }
  end

  def spot_summary
    spot_account = SpotAccount.find_or_create_default_for(@user)
    cash_balance = spot_account.cash_balance
    positions = Spot::PositionStateService.call(spot_account: spot_account)
    open_positions = positions.select(&:open?)
    if open_positions.empty?
      total = 0.to_d + cash_balance
      spot_cash_pct = total.positive? ? (cash_balance / total * 100).round(2) : nil
      return {
        spot_value: 0.to_d,
        spot_unrealized_pl: 0.to_d,
        spot_cost_basis: 0.to_d,
        spot_roi_pct: nil,
        spot_position_count: 0,
        spot_cash_balance: cash_balance,
        spot_cash_pct: spot_cash_pct,
        spot_chart_series: spot_cost_basis_series(spot_account)
      }
    end

    open_tokens = open_positions.map(&:token).uniq
    current_prices = Spot::CurrentPriceFetcher.call(user: @user, tokens: open_tokens)
    spot_value = open_positions.sum(BigDecimal("0")) { |pos| (current_prices[pos.token] || 0).to_d * pos.balance }
    spot_cost_basis = open_positions.sum(BigDecimal("0")) { |pos| pos.net_usd_invested.to_d }
    spot_unrealized_pl = open_positions.sum(BigDecimal("0")) do |pos|
      price = current_prices[pos.token]
      next 0.to_d unless price && pos.breakeven
      (price.to_d - pos.breakeven.to_d) * pos.balance
    end
    spot_roi_pct = spot_cost_basis.positive? ? (spot_unrealized_pl / spot_cost_basis * 100).round(2) : nil
    total = spot_value + cash_balance
    spot_cash_pct = total.positive? ? (cash_balance / total * 100).round(2) : nil

    {
      spot_value: spot_value,
      spot_unrealized_pl: spot_unrealized_pl,
      spot_cost_basis: spot_cost_basis,
      spot_roi_pct: spot_roi_pct,
      spot_position_count: open_positions.size,
      spot_cash_balance: cash_balance,
      spot_cash_pct: spot_cash_pct,
      spot_chart_series: spot_cost_basis_series(spot_account)
    }
  end

  def spot_cost_basis_series(spot_account)
    txs = spot_account.spot_transactions.trades.ordered_by_executed_at
    return [] if txs.empty?

    running = 0.to_d
    series = []
    txs.each do |tx|
      running += tx.side == "buy" ? tx.total_value_usd.to_d : -tx.total_value_usd.to_d
      series << { date: tx.executed_at.to_date.strftime("%b %d, %Y"), value: running.to_f }
    end
    series
  end
end
