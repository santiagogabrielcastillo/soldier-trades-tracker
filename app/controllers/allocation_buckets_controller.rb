# frozen_string_literal: true

class AllocationBucketsController < ApplicationController
  before_action :find_bucket, only: %i[update destroy]

  def create
    @bucket = current_user.allocation_buckets.build(bucket_params)
    if @bucket.save
      redirect_to allocation_path, notice: t("flash.allocation_bucket_created")
    else
      redirect_to allocation_path, alert: @bucket.errors.full_messages.first
    end
  end

  def update
    if @bucket.update(bucket_params)
      redirect_to allocation_path, notice: t("flash.allocation_bucket_updated")
    else
      redirect_to allocation_path, alert: @bucket.errors.full_messages.first
    end
  end

  def destroy
    @bucket.destroy
    redirect_to allocation_path, notice: t("flash.allocation_bucket_removed")
  end

  private

  def find_bucket
    @bucket = current_user.allocation_buckets.find(params[:id])
  end

  def bucket_params
    params.require(:allocation_bucket).permit(:name, :color, :target_pct)
  end
end
