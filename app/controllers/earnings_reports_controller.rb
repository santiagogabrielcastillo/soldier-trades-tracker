# frozen_string_literal: true

class EarningsReportsController < ApplicationController
  before_action :set_company
  before_action :set_report, only: %i[show edit update destroy]

  def new
    @report = @company.earnings_reports.build
    build_metric_value_fields
  end

  def create
    @report = @company.earnings_reports.build(report_params)
    if @report.save
      redirect_to company_earnings_report_path(@company, @report), notice: "Report added."
    else
      build_metric_value_fields
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def edit
    build_metric_value_fields
  end

  def update
    if @report.update(report_params)
      redirect_to company_earnings_report_path(@company, @report), notice: "Report updated."
    else
      build_metric_value_fields
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @report.destroy
    redirect_to company_path(@company), notice: "Report removed."
  end

  private

  def set_company
    @company = current_user.companies.find(params[:company_id])
  rescue ActiveRecord::RecordNotFound
    render plain: "Not found", status: :not_found
  end

  def set_report
    @report = @company.earnings_reports.find(params[:id])
  end

  def build_metric_value_fields
    existing_ids = @report.custom_metric_values.map(&:custom_metric_definition_id)
    @company.custom_metric_definitions.ordered.each do |defn|
      unless existing_ids.include?(defn.id)
        @report.custom_metric_values.build(custom_metric_definition: defn)
      end
    end
  end

  def report_params
    params.require(:earnings_report).permit(
      :period_type, :fiscal_year, :fiscal_quarter, :reported_on, :notes,
      :revenue, :net_income, :eps,
      custom_metric_values_attributes: %i[id custom_metric_definition_id decimal_value text_value]
    )
  end
end
