# frozen_string_literal: true

class Dashboards::SummaryService
  def self.call(user, mep_rate: nil)
    new(user, mep_rate: mep_rate).call
  end

  def initialize(user, mep_rate: nil)
    @user = user
    @mep_rate = mep_rate
  end

  def call
    @exchange_accounts = @user.exchange_accounts
    @default_portfolio = @user.default_portfolio

    base = if @default_portfolio
      portfolio_summary
    else
      all_time_summary
    end
    base.merge(spot_summary).merge(stocks_summary)
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
    current_prices = Spot::CurrentPriceFetcher.call(tokens: open_tokens)
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

  def stocks_summary
    stock_portfolio = StockPortfolio.find_or_create_default_for(@user)
    positions = Stocks::PositionStateService.call(stock_portfolio: stock_portfolio)
    open_positions = positions.select(&:open?)

    if open_positions.empty?
      return {
        stocks_value: 0.to_d,
        stocks_unrealized_pl: 0.to_d,
        stocks_cost_basis: 0.to_d,
        stocks_roi_pct: nil,
        stocks_position_count: 0,
        stocks_currency: stock_portfolio.argentina? ? :ars : :usd,
        stocks_pie_series: []
      }
    end

    open_tickers = open_positions.map(&:ticker).uniq

    # For Argentina-mode portfolios, prices and P&L are in ARS.
    # We attempt to convert to USD via the MEP rate for dashboard display.
    if stock_portfolio.argentina?
      current_prices = Stocks::ArgentineCurrentPriceFetcher.call(tickers: open_tickers, user: @user)
      mep_rate = @mep_rate
    else
      current_prices = Stocks::CurrentPriceFetcher.call(tickers: open_tickers, user: @user)
      mep_rate = nil
    end

    cash_balance = Stocks::CashBalanceService.call(stock_portfolio: stock_portfolio)
    stocks_value_native = open_positions.sum(BigDecimal("0")) { |pos| (current_prices[pos.ticker] || 0).to_d * pos.shares } + cash_balance
    stocks_cost_basis_native = open_positions.sum(BigDecimal("0")) { |pos| pos.net_usd_invested.to_d }
    stocks_unrealized_pl_native = open_positions.sum(BigDecimal("0")) do |pos|
      price = current_prices[pos.ticker]
      next 0.to_d unless price && pos.breakeven
      (price.to_d - pos.breakeven.to_d) * pos.shares
    end

    # Convert ARS → USD for dashboard when MEP rate is available; otherwise surface native values
    if stock_portfolio.argentina? && mep_rate&.positive?
      stocks_value = stocks_value_native / mep_rate
      stocks_cost_basis = stocks_cost_basis_native / mep_rate
      stocks_unrealized_pl = stocks_unrealized_pl_native / mep_rate
    else
      stocks_value = stocks_value_native
      stocks_cost_basis = stocks_cost_basis_native
      stocks_unrealized_pl = stocks_unrealized_pl_native
    end

    stocks_roi_pct = stocks_cost_basis.positive? ? (stocks_unrealized_pl / stocks_cost_basis * 100).round(2) : nil

    # Per-ticker allocation percentages for pie chart (uses native values — ARS or USD)
    position_values = open_positions.filter_map do |pos|
      value = (current_prices[pos.ticker] || 0).to_d * pos.shares
      { ticker: pos.ticker, value: value } if value.positive?
    end
    total_native = position_values.sum { |i| i[:value] }
    stocks_pie_series = if total_native.positive?
      position_values
        .map { |i| { ticker: i[:ticker], pct: (i[:value] / total_native * 100).round(1) } }
        .sort_by { |i| -i[:pct] }
    else
      []
    end

    {
      stocks_value: stocks_value,
      stocks_unrealized_pl: stocks_unrealized_pl,
      stocks_cost_basis: stocks_cost_basis,
      stocks_roi_pct: stocks_roi_pct,
      stocks_position_count: open_positions.size,
      stocks_currency: (stock_portfolio.argentina? && !mep_rate&.positive?) ? :ars : :usd,
      stocks_pie_series: stocks_pie_series
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
