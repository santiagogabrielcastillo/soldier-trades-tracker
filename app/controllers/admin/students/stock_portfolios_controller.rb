class Admin::Students::StockPortfoliosController < Admin::Students::BaseController
  before_action :set_portfolio, only: %i[edit update destroy]

  def index
    @portfolios = StockPortfolio.unscoped.where(user: @student)
  end

  def new
    @portfolio = @student.stock_portfolios.build
  end

  def create
    @portfolio = @student.stock_portfolios.build(portfolio_params)
    if @portfolio.save
      redirect_to admin_student_path(@student), notice: "Stock portfolio created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @portfolio.update(portfolio_params)
      redirect_to admin_student_path(@student), notice: "Stock portfolio updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @portfolio.discard!
    redirect_to admin_student_path(@student), notice: "Stock portfolio deleted."
  end

  private

  def set_portfolio
    @portfolio = StockPortfolio.unscoped.find_by!(id: params[:id], user: @student)
  end

  def portfolio_params
    params.require(:stock_portfolio).permit(:name, :market)
  end
end
