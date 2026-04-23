# frozen_string_literal: true

module Stocks
  class SectorPeThresholdsController < ApplicationController
    before_action :set_threshold

    def edit
    end

    def update
      if @threshold.update(threshold_params)
        redirect_to stocks_valuation_check_path(ticker: params[:ticker]), notice: "P/E thresholds updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_threshold
      sector = CGI.unescape(params[:sector])
      @threshold = SectorPeThreshold.find_by(sector: sector) ||
                   SectorPeThreshold.new(sector: sector, **SectorPeThreshold::DEFAULTS.fetch(sector, SectorPeThreshold::DEFAULTS["Default"]))
    end

    def threshold_params
      params.require(:sector_pe_threshold).permit(:gift_max, :attractive_max, :fair_max)
    end
  end
end
