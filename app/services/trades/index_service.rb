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
    current_prices = fetch_current_prices_for_open_positions(positions)

    {
      view: @view,
      portfolio: portfolio,
      positions: positions,
      current_prices: current_prices,
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

  def fetch_current_prices_for_open_positions(positions)
    open_positions = positions.select(&:open?)
    return {} if open_positions.empty?
    with_account = open_positions.select { |p| p.exchange_account.present? }
    open_positions.reject { |p| p.exchange_account.present? }.each do |p|
      Rails.logger.warn("[IndexService] Skipping position with nil exchange_account: symbol=#{p.symbol}")
    end
    open_positions = with_account
    return {} if open_positions.empty?
    by_provider = open_positions.group_by { |p| p.exchange_account.provider_type.to_s.presence || "bingx" }
    result = {}
    by_provider.each do |provider_type, group|
      symbols = group.map(&:symbol).uniq
      next if symbols.empty?
      prices = case provider_type
      when "binance" then Exchanges::Binance::TickerFetcher.fetch_prices(symbols: symbols)
      else Exchanges::Bingx::TickerFetcher.fetch_prices(symbols: symbols)
      end
      result.merge!(prices)
    end
    result
  end
end
