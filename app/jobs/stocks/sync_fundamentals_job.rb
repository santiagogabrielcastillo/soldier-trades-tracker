# frozen_string_literal: true

module Stocks
  class SyncFundamentalsJob < ApplicationJob
    queue_as :default

    def perform(tickers)
      results = Stocks::FundamentalsFetcher.call(tickers: tickers)
      now     = Time.current

      results.each do |ticker, f|
        StockFundamental.upsert(
          { ticker: ticker, pe: f.pe, fwd_pe: f.fwd_pe, peg: f.peg, ps: f.ps, pfcf: f.pfcf,
            net_margin: f.net_margin, roe: f.roe, roic: f.roic,
            debt_eq: f.debt_eq, sales_5y: f.sales_5y, sales_qq: f.sales_qq,
            sector: f.sector, industry: f.industry, ev_ebitda: f.ev_ebitda,
            eps_next_y: f.eps_next_y, eps_next_y_pct: f.eps_next_y_pct,
            fetched_at: now },
          unique_by: :ticker
        )
      end

      Rails.logger.info("[Stocks::SyncFundamentalsJob] Synced #{results.size}/#{tickers.size} tickers")
    end
  end
end
