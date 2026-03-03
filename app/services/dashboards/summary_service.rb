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

    if @default_portfolio
      portfolio_summary
    else
      all_time_summary
    end
  end

  private

  def portfolio_summary
    trades = @default_portfolio.trades_in_range.includes(:exchange_account).order(executed_at: :asc).limit(PositionSummary::TRADES_LIMIT)
    initial = @default_portfolio.initial_balance.to_d
    positions = PositionSummary.from_trades_with_balance(trades, initial_balance: initial)
    balance = initial + positions.sum(&:net_pl)
    analytics = build_analytics(positions, initial)

    {
      exchange_accounts: @exchange_accounts,
      default_portfolio: @default_portfolio,
      summary_label: @default_portfolio.name,
      summary_date_range: @default_portfolio.date_range_label,
      summary_period_pl: positions.sum(&:net_pl),
      summary_balance: balance,
      summary_position_count: positions.size,
      summary_trades_path_params: { view: "portfolio", portfolio_id: @default_portfolio.id }
    }.merge(analytics)
  end

  def all_time_summary
    trades = @user.trades.includes(:exchange_account).order(executed_at: :asc).limit(PositionSummary::TRADES_LIMIT)
    positions = PositionSummary.from_trades_with_balance(trades)
    analytics = build_analytics(positions, 0.to_d)

    {
      exchange_accounts: @exchange_accounts,
      default_portfolio: nil,
      summary_label: "All time",
      summary_date_range: nil,
      summary_period_pl: positions.sum(&:net_pl),
      summary_balance: positions.sum(&:net_pl),
      summary_position_count: positions.size,
      summary_trades_path_params: { view: "history" }
    }.merge(analytics)
  end

  def build_analytics(positions, initial_balance)
    # Closed = one row per closing leg (build_one_leg); open/single-fill rows have trades.size != 2 or no closing_leg?
    closed = positions.select do |s|
      s.trades.size == 2 && PositionSummary.closing_leg?(s.trades.last, s.trades.first)
    end
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

    balance_series = closed_sorted.map { |s| { date: (s.close_at || Time.current).iso8601, value: s.balance.to_f } }
    cumulative_pl_series = if initial_balance.present? && initial_balance.positive?
      closed_sorted.map { |s| { date: (s.close_at || Time.current).iso8601, value: (s.balance - initial_balance).to_f } }
    else
      cum = 0.to_d
      closed_sorted.map { |s| cum += s.net_pl; { date: (s.close_at || Time.current).iso8601, value: cum.to_f } }
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
end
