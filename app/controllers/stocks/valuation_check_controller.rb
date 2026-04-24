# frozen_string_literal: true

module Stocks
  class ValuationCheckController < ApplicationController
    def show
      @ticker = params[:ticker].to_s.strip.upcase.presence

      if @ticker
        fundamental = StockFundamental.find_by(ticker: @ticker)
        unless current_user.api_key_for(:finnhub)
          flash.now[:alert] = t("flash.stocks_finnhub_missing_html", link: view_context.link_to(t("flash.configure_here"), settings_api_keys_path, class: "underline"))
        end
        prices = Stocks::CurrentPriceFetcher.call(tickers: [ @ticker ], user: current_user)
        @price = prices[@ticker]

        @sector = fundamental&.sector
        @thresholds = SectorPeThreshold.for_sector(@sector)

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
