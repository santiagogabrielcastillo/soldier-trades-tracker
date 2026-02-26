# frozen_string_literal: true

class Portfolio < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :start_date, presence: true
  validate :end_date_after_start_date_if_present

  before_save :clear_other_defaults, if: :default?

  scope :default_first, -> { order(default: :desc, start_date: :desc) }

  def date_range_label
    return start_date.strftime("%b %d, %Y") if end_date.blank?
    "#{start_date.strftime("%b %d, %Y")} – #{end_date.strftime("%b %d, %Y")}"
  end

  def trades_in_range
    rel = user.trades.where("executed_at >= ?", start_date.beginning_of_day)
    rel = rel.where("executed_at <= ?", end_date.end_of_day) if end_date.present?
    rel
  end

  private

  def end_date_after_start_date_if_present
    return if end_date.blank? || start_date.blank?
    return if end_date >= start_date

    errors.add(:end_date, "must be on or after start date")
  end

  def clear_other_defaults
    return unless default?
    Portfolio.where(user_id: user_id).where.not(id: id).update_all(default: false)
  end
end
