# frozen_string_literal: true

class SpotController < ApplicationController
  MAX_CSV_SIZE = 10.megabytes

  def index
    @spot_account = SpotAccount.find_or_create_default_for(current_user)
    @positions = Spot::PositionStateService.call(spot_account: @spot_account)
    open_tokens = @positions.select(&:open?).map(&:token).uniq
    @current_prices = Spot::CurrentPriceFetcher.call(user: current_user, tokens: open_tokens)
  end

  def import
    @spot_account = current_user.spot_accounts.find_by(id: params[:spot_account_id])
    @spot_account ||= SpotAccount.find_or_create_default_for(current_user)

    unless params[:csv_file].present?
      redirect_to spot_path, alert: "Please select a CSV file." and return
    end

    file = params[:csv_file]
    if file.respond_to?(:size) && file.size > MAX_CSV_SIZE
      redirect_to spot_path, alert: "CSV file must be under #{MAX_CSV_SIZE / 1.megabyte} MB." and return
    end

    result = Spot::ImportFromCsvService.call(spot_account: @spot_account, csv_io: file)
    notice = "Imported #{result.created} row(s), #{result.skipped} skipped (duplicates)."
    notice += " Errors: #{result.errors.join('; ')}" if result.errors.any?
    redirect_to spot_path, notice: notice
  rescue ArgumentError => e
    redirect_to spot_path, alert: e.message
  end
end
