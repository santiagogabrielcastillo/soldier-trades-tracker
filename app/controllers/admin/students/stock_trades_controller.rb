class Admin::Students::StockTradesController < Admin::Students::BaseController
  before_action :set_stock_trade, only: %i[edit update destroy]

  def index
    trades = StockTrade.unscoped.where(
      stock_portfolio_id: @student.stock_portfolios.select(:id)
    ).order(executed_at: :desc)
    @pagy, @trades = pagy(:offset, trades, limit: 25)
    @stock_portfolios = @student.stock_portfolios
  end

  def new
    @trade = StockTrade.new
    @stock_portfolios = @student.stock_portfolios
  end

  def create
    @stock_portfolios = @student.stock_portfolios
    portfolio = @student.stock_portfolios.find_by(id: params[:stock_portfolio_id])
    unless portfolio
      redirect_to admin_student_path(@student), alert: "Stock portfolio not found." and return
    end
    @trade = portfolio.stock_trades.build(trade_params)
    if @trade.save
      redirect_to admin_student_path(@student), notice: "Stock trade created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @stock_portfolios = @student.stock_portfolios
  end

  def update
    if @trade.update(trade_params)
      redirect_to admin_student_path(@student), notice: "Stock trade updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @trade.discard!
    redirect_to admin_student_path(@student), notice: "Stock trade deleted."
  end

  private

  def set_stock_trade
    @trade = StockTrade.unscoped.find_by!(
      id: params[:id],
      stock_portfolio_id: @student.stock_portfolios.select(:id)
    )
  end

  def trade_params
    params.require(:stock_trade).permit(
      :ticker, :side, :price_usd, :shares, :total_value_usd,
      :executed_at, :row_signature
    )
  end
end
