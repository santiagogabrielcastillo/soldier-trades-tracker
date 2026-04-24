# frozen_string_literal: true

class PortfoliosController < ApplicationController
  before_action :set_portfolio, only: %i[edit update destroy set_default]

  def index
    @pagy, @portfolios = pagy(:offset, current_user.portfolios.default_first, limit: 25)
  end

  def new
    @portfolio = current_user.portfolios.build
  end

  def create
    @portfolio = current_user.portfolios.build(portfolio_params)
    if @portfolio.save
      redirect_to portfolios_path, notice: t("flash.portfolio_created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @portfolio.update(portfolio_params)
      redirect_to portfolios_path, notice: t("flash.portfolio_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @portfolio.destroy
    redirect_to portfolios_path, notice: t("flash.portfolio_removed")
  end

  def set_default
    @portfolio.update!(default: true)
    redirect_to portfolios_path, notice: t("flash.portfolio_set_default", name: @portfolio.name)
  end

  private

  def set_portfolio
    @portfolio = current_user.portfolios.find(params[:id])
  end

  def portfolio_params
    params.require(:portfolio).permit(:name, :start_date, :end_date, :initial_balance, :notes, :default, :exchange_account_id)
  end
end
