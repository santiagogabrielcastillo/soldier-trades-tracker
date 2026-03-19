# frozen_string_literal: true

class CedearInstrument < ApplicationRecord
  belongs_to :user

  validates :ticker, presence: true, uniqueness: { scope: :user_id }
  validates :ratio, presence: true, numericality: { greater_than: 0 }

  before_save { self.ticker = ticker.upcase.strip }
  before_save { self.underlying_ticker = underlying_ticker&.upcase&.strip }

  scope :ordered, -> { order(:ticker) }
end
