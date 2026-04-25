class Admin::Students::PortfoliosController < Admin::Students::BaseController
  before_action :set_portfolio, only: %i[edit update destroy]

  def index
    @portfolios = Portfolio.unscoped.where(user: @student).order(start_date: :desc)
  end

  def new
    @portfolio = @student.portfolios.build
  end

  def create
    @portfolio = @student.portfolios.build(portfolio_params)
    if @portfolio.save
      redirect_to admin_student_path(@student), notice: "Portfolio created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @portfolio.update(portfolio_params)
      redirect_to admin_student_path(@student), notice: "Portfolio updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @portfolio.discard!
    redirect_to admin_student_path(@student), notice: "Portfolio deleted."
  end

  private

  def set_portfolio
    @portfolio = Portfolio.unscoped.find_by!(id: params[:id], user: @student)
  end

  def portfolio_params
    params.require(:portfolio).permit(:name, :start_date, :end_date, :exchange_account_id)
  end
end
