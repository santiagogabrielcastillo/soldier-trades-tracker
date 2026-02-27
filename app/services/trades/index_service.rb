# frozen_string_literal: true

class Trades::IndexService
  PAGY_LIMIT = 25

  def self.call(user:, view: nil, portfolio_id: nil)
    new(user: user, view: view, portfolio_id: portfolio_id).call
  end

  def initialize(user:, view: nil, portfolio_id: nil)
    @user = user
    @view = (view.to_s == "portfolio") ? "portfolio" : "history"
    @portfolio_id = portfolio_id
  end

  def call
    portfolio = resolve_portfolio
    trades = load_trades(portfolio)
    initial_balance = portfolio&.initial_balance.to_d
    positions = PositionSummary.from_trades_with_balance(trades, initial_balance: initial_balance)

    {
      view: @view,
      portfolio: portfolio,
      positions: positions,
      initial_balance: initial_balance,
      portfolios: @view == "portfolio" ? @user.portfolios.default_first : nil
    }
  end

  private

  def resolve_portfolio
    return nil unless @view == "portfolio"
    return @user.portfolios.find_by(id: @portfolio_id) if @portfolio_id.present?
    @user.default_portfolio
  end

  def load_trades(portfolio)
    relation = if portfolio
      portfolio.trades_in_range.includes(:exchange_account)
    else
      @user.trades.includes(:exchange_account)
    end
    relation.order(executed_at: :asc).limit(PositionSummary::TRADES_LIMIT)
  end
end
