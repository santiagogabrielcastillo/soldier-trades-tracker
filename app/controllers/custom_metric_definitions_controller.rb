# frozen_string_literal: true

class CustomMetricDefinitionsController < ApplicationController
  before_action :set_company

  def create
    @definition = @company.custom_metric_definitions.build(
      name: params[:name],
      data_type: params[:data_type]
    )
    if @definition.save
      redirect_to company_path(@company), notice: "#{@definition.name} metric added."
    else
      redirect_to company_path(@company), alert: @definition.errors.full_messages.to_sentence
    end
  end

  def destroy
    definition = @company.custom_metric_definitions.find(params[:id])
    definition.destroy
    redirect_to company_path(@company), notice: "#{definition.name} metric removed."
  end

  private

  def set_company
    @company = current_user.companies.find(params[:company_id])
  rescue ActiveRecord::RecordNotFound
    render plain: "Not found", status: :not_found
  end
end
