# frozen_string_literal: true

module Stocks
  class AnalysisController < ApplicationController
    def show
      ticker    = params[:ticker].to_s.strip.upcase
      @analysis = StockAnalysis.find_by!(user: current_user, ticker: ticker)
      @fundamental = StockFundamental.for_tickers([ ticker ])[ticker]
    rescue ActiveRecord::RecordNotFound
      redirect_to stocks_path, alert: "No analysis found for #{params[:ticker].upcase}."
    end
  end
end
