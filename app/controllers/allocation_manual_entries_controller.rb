# frozen_string_literal: true

class AllocationManualEntriesController < ApplicationController
  before_action :find_entry, only: %i[update destroy]

  def create
    @entry = current_user.allocation_manual_entries.build(entry_params)
    if @entry.save
      redirect_to allocation_path, notice: "Entry added."
    else
      redirect_to allocation_path, alert: @entry.errors.full_messages.first
    end
  end

  def update
    if @entry.update(entry_params)
      redirect_to allocation_path, notice: "Entry updated."
    else
      redirect_to allocation_path, alert: @entry.errors.full_messages.first
    end
  end

  def destroy
    @entry.destroy
    redirect_to allocation_path, notice: "Entry removed."
  end

  private

  def find_entry
    @entry = current_user.allocation_manual_entries.find(params[:id])
  end

  def entry_params
    params.require(:allocation_manual_entry).permit(:allocation_bucket_id, :label, :amount_usd)
  end
end
