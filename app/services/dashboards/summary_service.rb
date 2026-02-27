# frozen_string_literal: true

class Dashboards::SummaryService
  TRADES_LIMIT = 2000

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
    trades = @default_portfolio.trades_in_range.includes(:exchange_account).order(executed_at: :asc).limit(TRADES_LIMIT)
    positions = PositionSummary.from_trades(trades)
    PositionSummary.assign_balance!(positions, initial_balance: @default_portfolio.initial_balance.to_d)

    {
      exchange_accounts: @exchange_accounts,
      default_portfolio: @default_portfolio,
      summary_label: @default_portfolio.name,
      summary_date_range: @default_portfolio.date_range_label,
      summary_period_pl: positions.sum(&:net_pl),
      summary_balance: @default_portfolio.initial_balance.to_d + positions.sum(&:net_pl),
      summary_position_count: positions.size,
      summary_trades_path_params: { view: "portfolio", portfolio_id: @default_portfolio.id }
    }
  end

  def all_time_summary
    trades = @user.trades.includes(:exchange_account).order(executed_at: :asc).limit(TRADES_LIMIT)
    positions = PositionSummary.from_trades(trades)
    PositionSummary.assign_balance!(positions)

    {
      exchange_accounts: @exchange_accounts,
      default_portfolio: nil,
      summary_label: "All time",
      summary_date_range: nil,
      summary_period_pl: positions.sum(&:net_pl),
      summary_balance: positions.sum(&:net_pl),
      summary_position_count: positions.size,
      summary_trades_path_params: { view: "history" }
    }
  end
end
