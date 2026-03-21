# frozen_string_literal: true

class WatchlistTicker < ApplicationRecord
  belongs_to :user

  before_validation { self.ticker = ticker.to_s.strip.upcase }

  validates :ticker, presence: true, uniqueness: { scope: :user_id }

  scope :ordered, -> { order(:ticker) }
end
