# frozen_string_literal: true

module Stocks
  class ValuationCheckController < ApplicationController
    def show
      @ticker = params[:ticker].to_s.strip.upcase.presence

      if @ticker
        fundamental = StockFundamental.find_by(ticker: @ticker)
        prices = Stocks::CurrentPriceFetcher.call(tickers: [@ticker])
        @price = prices[@ticker]

        if fundamental
          @fwd_eps = if fundamental.eps_next_y&.positive?
                       fundamental.eps_next_y.round(2)
                     elsif @price && fundamental.fwd_pe&.positive?
                       (@price / fundamental.fwd_pe).round(2)
                     end
          @growth = fundamental.eps_next_y_pct&.round(2)
        end
      end
    end
  end
end
