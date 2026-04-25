# frozen_string_literal: true

class Portfolio < ApplicationRecord
  include Auditable
  include Discardable
  include HasSingleDefault

  belongs_to :user
  belongs_to :exchange_account, optional: true

  validates :name, presence: true
  validates :start_date, presence: true
  validate :end_date_after_start_date_if_present
  validate :exchange_account_belongs_to_user, if: :exchange_account_id?

  scope :default_first, -> { order(default: :desc, start_date: :desc) }

  def date_range_label
    return start_date.strftime("%b %d, %Y") if end_date.blank?
    "#{start_date.strftime("%b %d, %Y")} – #{end_date.strftime("%b %d, %Y")}"
  end

  def trades_in_range
    rel = user.trades.where("executed_at >= ?", start_date.beginning_of_day)
    rel = rel.where("executed_at <= ?", end_date.end_of_day) if end_date.present?
    rel = rel.where(exchange_account_id: exchange_account_id) if exchange_account_id.present?
    rel
  end

  private

  def end_date_after_start_date_if_present
    return if end_date.blank? || start_date.blank?
    return if end_date >= start_date

    errors.add(:end_date, "must be on or after start date")
  end

  def exchange_account_belongs_to_user
    return if exchange_account_id.blank? || user_id.blank?
    return if user.exchange_accounts.exists?(exchange_account_id)

    errors.add(:exchange_account_id, "must be one of your exchange accounts")
  end

end
