# frozen_string_literal: true

class StockFundamental < ApplicationRecord
  validates :ticker, presence: true, uniqueness: true
  validates :fetched_at, presence: true

  def self.for_tickers(tickers)
    where(ticker: tickers).index_by(&:ticker)
  end
end
