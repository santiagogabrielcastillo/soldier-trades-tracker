# frozen_string_literal: true

module Stocks
  class ValuationCheckController < ApplicationController
    def show
      @ticker = params[:ticker].to_s.strip.upcase.presence

      if @ticker
        fundamental = StockFundamental.find_by(ticker: @ticker)
        prices = Stocks::CurrentPriceFetcher.call(tickers: [@ticker])
        @price = prices[@ticker]

        if @price && fundamental&.fwd_pe&.positive?
          @fwd_eps = (@price / fundamental.fwd_pe).round(2)
        end
      end
    end
  end
end
