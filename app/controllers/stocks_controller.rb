# frozen_string_literal: true

class StocksController < ApplicationController
  def index
    @stock_portfolio = StockPortfolio.find_or_create_default_for(current_user)
    @view = (params[:view].to_s == "transactions") ? "transactions" : "portfolio"

    if @view == "transactions"
      relation = load_stock_trades_filtered
      @pagy, @trades = pagy(:offset, relation, limit: 25)
      @from_date = params[:from_date].presence
      @to_date = params[:to_date].presence
      @filter_ticker = params[:ticker].presence
      @filter_side = params[:side].presence if params[:side].to_s.in?(%w[buy sell])
      @tickers_for_filter = @stock_portfolio.stock_trades.distinct.pluck(:ticker).sort
    else
      load_portfolio_data
    end
  end

  def create
    @stock_portfolio = StockPortfolio.find_or_create_default_for(current_user)
    permitted = stock_trade_params
    side = permitted[:side].to_s.strip.downcase.presence
    side = nil unless side&.in?(%w[buy sell])
    ticker = permitted[:ticker].to_s.strip.upcase.presence
    executed_at = parse_executed_at(permitted[:executed_at])
    shares = parse_decimal_param(permitted[:shares])
    price_usd = parse_decimal_param(permitted[:price_usd])

    if side && ticker && executed_at && shares&.positive? && price_usd&.positive?
      total_value_usd = shares * price_usd
      row_signature = Digest::SHA256.hexdigest("#{ticker}|#{side}|#{executed_at.to_i}|#{price_usd}|#{shares}")
      trade = @stock_portfolio.stock_trades.build(
        ticker: ticker,
        side: side,
        executed_at: executed_at,
        price_usd: price_usd,
        shares: shares,
        total_value_usd: total_value_usd,
        row_signature: row_signature
      )
      if trade.save
        redirect_to stocks_path, notice: "Trade added." and return
      end
      if trade.errors[:row_signature].any?
        redirect_to stocks_path, alert: "This trade already exists." and return
      end
      @stock_trade = trade
    else
      @stock_trade = StockTrade.new(
        stock_portfolio: @stock_portfolio,
        ticker: ticker,
        side: side,
        executed_at: executed_at,
        shares: shares,
        price_usd: price_usd,
        row_signature: SecureRandom.hex(32)
      ).tap(&:validate)
    end

    @view = "portfolio"
    load_portfolio_data
    @open_new_trade_modal = true
    render :index, status: :unprocessable_entity
  end

  private

  def parse_executed_at(value)
    return nil if value.blank?
    Time.zone.parse(value.to_s)
  end

  def parse_decimal_param(value)
    return nil if value.blank?
    BigDecimal(value.to_s.gsub(",", ""))
  rescue ArgumentError, TypeError
    nil
  end

  def load_stock_trades_filtered
    relation = @stock_portfolio.stock_trades.newest_first
    relation = relation.where("executed_at >= ?", params[:from_date].to_date.beginning_of_day) if params[:from_date].present?
    relation = relation.where("executed_at <= ?", params[:to_date].to_date.end_of_day) if params[:to_date].present?
    relation = relation.where(ticker: params[:ticker].to_s.upcase) if params[:ticker].present?
    relation = relation.where(side: params[:side]) if params[:side].to_s.in?(%w[buy sell])
    relation
  rescue ArgumentError, TypeError
    @stock_portfolio.stock_trades.newest_first
  end

  def load_portfolio_data
    all_positions = Stocks::PositionStateService.call(stock_portfolio: @stock_portfolio)
    open_positions = all_positions.select(&:open?)
    open_tickers = open_positions.map(&:ticker).uniq
    @current_prices = Stocks::CurrentPriceFetcher.call(tickers: open_tickers)
    @positions = open_positions.sort_by { |pos| -((@current_prices[pos.ticker] || 0).to_d * pos.shares) }
    @stocks_value = open_positions.sum(BigDecimal("0")) { |pos| (@current_prices[pos.ticker] || 0).to_d * pos.shares }
  end

  def stock_trade_params
    params.permit(:ticker, :side, :shares, :price_usd, :executed_at)
  end
end
