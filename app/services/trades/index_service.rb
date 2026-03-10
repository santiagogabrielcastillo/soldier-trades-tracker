# frozen_string_literal: true

class Trades::IndexService
  PAGY_LIMIT = 25

  def self.call(user:, view: nil, portfolio_id: nil, exchange_account_id: nil, from_date: nil, to_date: nil)
    new(
      user: user,
      view: view,
      portfolio_id: portfolio_id,
      exchange_account_id: exchange_account_id,
      from_date: from_date,
      to_date: to_date
    ).call
  end

  def initialize(user:, view: nil, portfolio_id: nil, exchange_account_id: nil, from_date: nil, to_date: nil)
    @user = user
    @view = normalize_view(view, exchange_account_id)
    @portfolio_id = portfolio_id
    @exchange_account_id = exchange_account_id
    @from_date = from_date
    @to_date = to_date
  end

  def call
    portfolio = resolve_portfolio
    trades = load_trades(portfolio)
    initial_balance = portfolio&.initial_balance.to_d
    leverage_by_symbol = Positions::CurrentDataFetcher.leverage_by_symbol(trades)
    positions = PositionSummary.from_trades_with_balance(trades, initial_balance: initial_balance, leverage_by_symbol: leverage_by_symbol)
    current_prices = Positions::CurrentDataFetcher.current_prices_for_open_positions(positions)
    exchange_account = @exchange_account_id.present? ? @user.exchange_accounts.find_by(id: @exchange_account_id) : nil

    {
      view: @view,
      portfolio: portfolio,
      positions: positions,
      current_prices: current_prices,
      initial_balance: initial_balance,
      portfolios: @view == "portfolio" ? @user.portfolios.default_first : nil,
      exchange_account: exchange_account,
      exchange_accounts: @user.exchange_accounts.to_a,
      from_date: @from_date,
      to_date: @to_date
    }
  end

  private

  def normalize_view(view, exchange_account_id)
    return "portfolio" if view.to_s == "portfolio"
    return "exchange" if view.to_s == "exchange" && exchange_account_id.present?
    "history"
  end

  def resolve_portfolio
    return nil unless @view == "portfolio"
    return @user.portfolios.includes(:exchange_account).find_by(id: @portfolio_id) if @portfolio_id.present?
    @user.default_portfolio
  end

  def load_trades(portfolio)
    relation = if portfolio
      portfolio.trades_in_range.includes(:exchange_account)
    elsif @view == "exchange" && @exchange_account_id.present?
      @user.trades.where(exchange_account_id: @exchange_account_id).includes(:exchange_account)
    else
      @user.trades.includes(:exchange_account)
    end
    unless portfolio
      relation = relation.where("executed_at >= ?", @from_date.to_date.beginning_of_day) if @from_date.present?
      relation = relation.where("executed_at <= ?", @to_date.to_date.end_of_day) if @to_date.present?
      relation = relation.where(exchange_account_id: @exchange_account_id) if @view == "history" && @exchange_account_id.present?
    end
    relation.order(executed_at: :asc).limit(PositionSummary::TRADES_LIMIT)
  end
end
