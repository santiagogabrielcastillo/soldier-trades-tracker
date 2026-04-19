# frozen_string_literal: true

class StocksController < ApplicationController
  def index
    @stock_portfolio = resolve_portfolio
    @view = params[:view].to_s.in?(%w[transactions performance valuations watchlist]) ? params[:view] : "portfolio"
    @all_portfolios = current_user.stock_portfolios.default_first

    case @view
    when "transactions"
      relation = load_stock_trades_filtered
      @pagy, @trades = pagy(:offset, relation, limit: 25)
      @from_date = params[:from_date].presence
      @to_date = params[:to_date].presence
      @filter_ticker = params[:ticker].presence
      @filter_side = params[:side].presence if params[:side].to_s.in?(%w[buy sell])
      @tickers_for_filter = @stock_portfolio.stock_trades.distinct.pluck(:ticker).sort
    when "performance"
      @twr_series = Stocks::TwrCalculatorService.call(stock_portfolio: @stock_portfolio)
      @snapshots = @stock_portfolio.stock_portfolio_snapshots.ordered.to_a.reverse
    when "valuations"
      all_positions = Stocks::PositionStateService.call(stock_portfolio: @stock_portfolio)
      @positions    = all_positions.select(&:open?)
      tickers       = @positions.map(&:ticker)
      @fundamentals = StockFundamental.for_tickers(tickers)
      @analyses     = StockAnalysis.for_user_and_tickers(current_user, tickers)
    when "watchlist"
      @watchlist_tickers = current_user.watchlist_tickers.ordered
      tickers            = @watchlist_tickers.pluck(:ticker)
      @fundamentals      = StockFundamental.for_tickers(tickers)
      @analyses          = StockAnalysis.for_user_and_tickers(current_user, tickers)
    else
      load_portfolio_data
    end
  end

  def record_snapshot
    @stock_portfolio = resolve_portfolio
    amount = parse_decimal_param(params[:cash_flow_amount])
    type   = params[:entry_type].to_s

    cash_flow = case type
    when "deposit"    then amount&.positive? ? amount : nil
    when "withdrawal" then amount&.positive? ? -amount : nil
    else BigDecimal("0")
    end

    if type.in?(%w[deposit withdrawal]) && cash_flow.nil?
      redirect_to stocks_path(portfolio_id: @stock_portfolio.id, view: "performance"),
                  alert: "Enter a positive amount." and return
    end

    Stocks::PortfolioSnapshotService.call(stock_portfolio: @stock_portfolio, cash_flow: cash_flow || 0)
    redirect_to stocks_path(portfolio_id: @stock_portfolio.id, view: "performance"),
                notice: type == "snapshot" ? "Snapshot recorded." : "Cash flow recorded."
  rescue => e
    Rails.logger.error("[StocksController#record_snapshot] #{e.message}")
    redirect_to stocks_path(portfolio_id: @stock_portfolio.id, view: "performance"),
                alert: "Could not fetch current prices. Try again later."
  end

  def sync_fundamentals
    @stock_portfolio = resolve_portfolio
    tickers = Stocks::PositionStateService.call(stock_portfolio: @stock_portfolio)
                .select(&:open?).map(&:ticker).uniq
    Stocks::SyncFundamentalsJob.perform_later(tickers)
    redirect_to stocks_path(portfolio_id: @stock_portfolio.id, view: "valuations"),
                notice: "Sync started — refresh in a moment to see updated data."
  end

  def sync_watchlist
    tickers = current_user.watchlist_tickers.pluck(:ticker)
    Stocks::SyncFundamentalsJob.perform_later(tickers)
    redirect_to stocks_path(view: "watchlist"),
                notice: "Sync started — refresh in a moment to see updated data."
  end

  def analyze_ticker
    ticker = params[:ticker].to_s.strip.upcase
    unless allowed_analysis_tickers.include?(ticker)
      redirect_back fallback_location: stocks_path, alert: "Ticker not found." and return
    end
    Stocks::SyncStockAnalysisJob.perform_later(current_user.id, [ticker])
    redirect_back fallback_location: stocks_path, notice: "Analysis started — refresh in a moment."
  end

  def add_to_watchlist
    ticker = params[:ticker].to_s.strip.upcase.presence
    if ticker
      current_user.watchlist_tickers.find_or_create_by(ticker: ticker)
    end
    redirect_to stocks_path(view: "watchlist")
  end

  def remove_from_watchlist
    current_user.watchlist_tickers.find(params[:id]).destroy
    redirect_to stocks_path(view: "watchlist")
  end

  def destroy_snapshot
    @stock_portfolio = resolve_portfolio
    snapshot = @stock_portfolio.stock_portfolio_snapshots.find(params[:id])
    snapshot.destroy!
    redirect_to stocks_path(portfolio_id: @stock_portfolio.id, view: "performance"),
                notice: "Entry deleted."
  end

  def create
    @stock_portfolio = resolve_portfolio
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
      cedear_ratio = resolve_cedear_ratio(ticker) if @stock_portfolio.argentina?
      trade = @stock_portfolio.stock_trades.build(
        ticker: ticker,
        side: side,
        executed_at: executed_at,
        price_usd: price_usd,
        shares: shares,
        total_value_usd: total_value_usd,
        row_signature: row_signature,
        cedear_ratio: cedear_ratio
      )
      if trade.save
        redirect_to stocks_path(portfolio_id: @stock_portfolio.id), notice: "Trade added." and return
      end
      if trade.errors[:row_signature].any?
        redirect_to stocks_path(portfolio_id: @stock_portfolio.id), alert: "This trade already exists." and return
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
    @all_portfolios = current_user.stock_portfolios.default_first
    load_portfolio_data
    @open_new_trade_modal = true
    render :index, status: :unprocessable_entity
  end

  private

  def allowed_analysis_tickers
    portfolio = StockPortfolio.find_or_create_default_for(current_user)
    open = Stocks::PositionStateService.call(stock_portfolio: portfolio)
             .select(&:open?).map(&:ticker)
    watchlist = current_user.watchlist_tickers.pluck(:ticker)
    (open + watchlist).uniq
  end

  def resolve_portfolio
    if params[:portfolio_id].present?
      current_user.stock_portfolios.find_by(id: params[:portfolio_id]) ||
        StockPortfolio.find_or_create_default_for(current_user)
    else
      StockPortfolio.find_or_create_default_for(current_user)
    end
  end

  def resolve_cedear_ratio(ticker)
    current_user.cedear_instruments.find_by(ticker: ticker)&.ratio
  end

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

    if @stock_portfolio.argentina?
      unless current_user.api_key_for(:iol)
        flash.now[:alert] = "Argentine stock prices require IOL credentials. #{view_context.link_to('Configure them here', settings_api_keys_path, class: 'underline')}".html_safe
      end
      prices_thread = Thread.new { Stocks::ArgentineCurrentPriceFetcher.call(tickers: open_tickers, user: current_user) }
      mep_thread    = Thread.new { Stocks::MepRateFetcher.call }
      @current_prices    = prices_thread.value
      @mep_rate          = mep_thread.value
      @cedear_instruments = current_user.cedear_instruments.where(ticker: open_tickers).index_by(&:ticker)
    else
      unless current_user.api_key_for(:finnhub)
        flash.now[:alert] = "Stock prices require a Finnhub API key. #{view_context.link_to('Configure it here', settings_api_keys_path, class: 'underline')}".html_safe
      end
      @current_prices = Stocks::CurrentPriceFetcher.call(tickers: open_tickers, user: current_user)
      @mep_rate = nil
      @cedear_instruments = {}
    end

    @positions = open_positions.sort_by { |pos| -((@current_prices[pos.ticker] || 0).to_d * pos.shares) }
    positions_market_value = open_positions.sum(BigDecimal("0")) { |pos| (@current_prices[pos.ticker] || 0).to_d * pos.shares }
    @cash_balance = Stocks::CashBalanceService.call(stock_portfolio: @stock_portfolio)
    @stocks_value = positions_market_value + @cash_balance
    @total_unrealized_pnl = open_positions.sum(BigDecimal("0")) do |pos|
      price = @current_prices[pos.ticker]
      next BigDecimal("0") unless price && pos.breakeven&.positive?
      (price.to_d - pos.breakeven.to_d) * pos.shares
    end
    @stocks_chart_data = build_stocks_chart_data
  end

  def build_stocks_chart_data
    return { pie: [], bar: [] } if @positions.empty? && !@cash_balance&.positive?

    pie = @positions.filter_map do |pos|
      value = (@current_prices[pos.ticker] || 0).to_d * pos.shares
      next unless value.positive? && @stocks_value.positive?
      { ticker: pos.ticker, pct: (value / @stocks_value * 100).round(1) }
    end.sort_by { |d| -d[:pct] }

    if @cash_balance&.positive? && @stocks_value.positive?
      pie << { ticker: "CASH", pct: (@cash_balance / @stocks_value * 100).round(1) }
    end

    bar = @positions.filter_map do |pos|
      price = @current_prices[pos.ticker]
      next unless price && pos.breakeven&.positive?
      pct = ((price.to_d - pos.breakeven.to_d) / pos.breakeven.to_d * 100).to_f.round(2)
      { ticker: pos.ticker, pct: pct }
    end.sort_by { |d| -d[:pct] }

    { pie: pie, bar: bar }
  end

  def stock_trade_params
    params.permit(:ticker, :side, :shares, :price_usd, :executed_at)
  end

end
