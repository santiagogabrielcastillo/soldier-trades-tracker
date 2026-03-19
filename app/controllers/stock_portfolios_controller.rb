# frozen_string_literal: true

class StockPortfoliosController < ApplicationController
  before_action :set_portfolio, only: %i[edit update]

  def index
    @stock_portfolios = current_user.stock_portfolios.default_first
  end

  def new
    @stock_portfolio = current_user.stock_portfolios.build
  end

  def create
    @stock_portfolio = current_user.stock_portfolios.build(portfolio_params)
    if @stock_portfolio.save
      redirect_to stocks_path, notice: "Portfolio created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @stock_portfolio.update(portfolio_params)
      redirect_to stocks_path, notice: "Portfolio updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_portfolio
    @stock_portfolio = current_user.stock_portfolios.find(params[:id])
  end

  def portfolio_params
    params.require(:stock_portfolio).permit(:name, :market, :default)
  end
end
