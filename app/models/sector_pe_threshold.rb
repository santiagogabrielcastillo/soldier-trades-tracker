# frozen_string_literal: true

class SectorPeThreshold < ApplicationRecord
  DEFAULTS = {
    "Technology"              => { gift_max: 20, attractive_max: 30, fair_max: 50 },
    "Semiconductors"          => { gift_max: 15, attractive_max: 25, fair_max: 40 },
    "Financial"               => { gift_max: 8,  attractive_max: 12, fair_max: 20 },
    "Healthcare"              => { gift_max: 12, attractive_max: 18, fair_max: 30 },
    "Consumer Cyclical"       => { gift_max: 12, attractive_max: 18, fair_max: 30 },
    "Consumer Defensive"      => { gift_max: 12, attractive_max: 17, fair_max: 25 },
    "Energy"                  => { gift_max: 8,  attractive_max: 12, fair_max: 20 },
    "Utilities"               => { gift_max: 10, attractive_max: 15, fair_max: 22 },
    "Industrials"             => { gift_max: 12, attractive_max: 18, fair_max: 28 },
    "Communication Services"  => { gift_max: 12, attractive_max: 20, fair_max: 35 },
    "Real Estate"             => { gift_max: 15, attractive_max: 25, fair_max: 40 },
    "Basic Materials"         => { gift_max: 10, attractive_max: 15, fair_max: 25 },
    "Default"                 => { gift_max: 10, attractive_max: 15, fair_max: 30 },
  }.freeze

  validates :sector, presence: true, uniqueness: true
  validates :gift_max, :attractive_max, :fair_max, presence: true, numericality: { greater_than: 0 }
  validate :thresholds_ascending

  def self.for_sector(sector)
    return default_record unless sector.present?

    find_by(sector: sector) || default_record
  end

  def self.default_record
    find_by(sector: "Default") || new(sector: "Default", **DEFAULTS["Default"])
  end

  def as_json_thresholds
    { gift_max: gift_max.to_f, attractive_max: attractive_max.to_f, fair_max: fair_max.to_f }
  end

  private

  def thresholds_ascending
    return unless gift_max && attractive_max && fair_max

    errors.add(:attractive_max, "must be greater than gift max") if attractive_max <= gift_max
    errors.add(:fair_max, "must be greater than attractive max") if fair_max <= attractive_max
  end
end
