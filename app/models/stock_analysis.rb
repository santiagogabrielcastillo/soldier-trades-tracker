# frozen_string_literal: true

class StockAnalysis < ApplicationRecord
  belongs_to :user

  validates :ticker,      presence: true
  validates :rating,      presence: true
  validates :analyzed_at, presence: true

  def self.for_user_and_tickers(user, tickers)
    where(user: user, ticker: tickers).index_by(&:ticker)
  end
end
