# frozen_string_literal: true

class CompaniesController < ApplicationController
  before_action :set_company, only: %i[show edit update destroy comparison]

  def index
    @companies = current_user.companies.ordered
  end

  def show
    @custom_metric_definitions = @company.custom_metric_definitions.ordered
    @reports = @company.earnings_reports.order(Arel.sql("fiscal_year DESC, fiscal_quarter DESC NULLS LAST"))
  end

  def new
    @company = current_user.companies.build
  end

  def create
    @company = current_user.companies.build(company_params)
    if @company.save
      redirect_to company_path(@company), notice: t("flash.company_added", ticker: @company.ticker)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @company.update(company_params)
      redirect_to company_path(@company), notice: t("flash.company_updated", ticker: @company.ticker)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @company.destroy
    redirect_to companies_path, notice: t("flash.company_removed", ticker: @company.ticker)
  end

  def comparison
    @definitions = @company.custom_metric_definitions.ordered
    @reports = @company.earnings_reports
      .includes(custom_metric_values: :custom_metric_definition)
      .order(Arel.sql("fiscal_year DESC, fiscal_quarter DESC NULLS LAST"))
    @values_by_report = @reports.each_with_object({}) do |report, h|
      h[report.id] = report.custom_metric_values.index_by(&:custom_metric_definition_id)
    end
  end

  private

  def set_company
    @company = current_user.companies.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render plain: "Not found", status: :not_found
  end

  def company_params
    params.require(:company).permit(:ticker, :name, :sector, :description)
  end
end
