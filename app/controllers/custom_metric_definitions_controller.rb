# frozen_string_literal: true

class CustomMetricDefinitionsController < ApplicationController
  before_action :set_company
  before_action :set_definition, only: %i[edit update]

  def create
    @definition = @company.custom_metric_definitions.build(create_params)
    if @definition.save
      redirect_to company_path(@company), notice: "#{@definition.name} metric added."
    else
      redirect_to company_path(@company), alert: @definition.errors.full_messages.to_sentence
    end
  end

  def edit
  end

  def update
    if @definition.update(update_params)
      redirect_to company_path(@company), notice: "#{@definition.name} metric updated."
    else
      render :edit, status: :unprocessable_entity
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

  def set_definition
    @definition = @company.custom_metric_definitions.find(params[:id])
  end

  def create_params
    params.permit(:name, :data_type)
  end

  def update_params
    params.require(:custom_metric_definition).permit(:name, :data_type)
  end
end
