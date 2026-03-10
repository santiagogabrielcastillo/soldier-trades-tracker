# frozen_string_literal: true

# Persisted position row derived from Trade data. One row per position (same granularity as PositionSummary).
# Rebuilt after sync via Positions::RebuildForAccountService. Balance is assigned at read time (assign_balance!).
class Position < ApplicationRecord
  belongs_to :exchange_account
  has_many :position_trades, dependent: :destroy
  has_many :trades, through: :position_trades

  attr_accessor :balance

  scope :open_positions, -> { where(open: true) }
  scope :closed_positions, -> { where(open: false) }
  scope :for_exchange_account, ->(id) { where(exchange_account_id: id) }
  scope :for_user, ->(user) { where(exchange_account_id: user.exchange_account_ids) }

  # Positions that overlap the given date range (open_at <= to_date and (close_at nil or close_at >= from_date)).
  scope :in_date_range, ->(from_date, to_date) {
    rel = all
    if from_date.present?
      rel = rel.where("close_at IS NULL OR close_at >= ?", from_date.to_date.beginning_of_day)
    end
    if to_date.present?
      rel = rel.where("open_at <= ?", to_date.to_date.end_of_day)
    end
    rel
  }

  # Display order: open first, then closed by close_at desc (same as PositionSummary).
  scope :ordered_for_display, -> {
    order(Arel.sql("open DESC NULLS LAST"), close_at: :desc, open_at: :desc)
  }

  # Assign running balance (newest first). Same semantics as PositionSummary.assign_balance!.
  def self.assign_balance!(positions, initial_balance: 0)
    list = positions.is_a?(ActiveRecord::Relation) ? positions.to_a : positions
    base = initial_balance.to_d
    total = list.sum(&:net_pl)
    list.each do |p|
      p.balance = base + total
      total -= p.net_pl
    end
    list
  end

  # ROI = (net_pl / margin_used) * 100 for closed positions. Nil when margin zero or open.
  def roi_percent
    return nil if open?
    return nil if margin_used.blank? || margin_used.zero?
    (net_pl / margin_used * 100).round(2)
  end

  # Unrealized PnL at current_price. Long: (current - entry) * qty; short: (entry - current) * qty.
  def unrealized_pnl(current_price)
    return nil unless open?
    return nil if current_price.blank?
    price = current_price.to_d
    return nil if entry_price.blank? || entry_price.zero?
    return nil if open_quantity.blank? || open_quantity.zero?
    diff = case position_side
    when "long" then (price - entry_price) * open_quantity
    when "short" then (entry_price - price) * open_quantity
    else nil
    end
    diff&.round(8)
  end

  # Unrealized ROI percent: (unrealized_pnl / margin_used) * 100.
  def unrealized_roi_percent(current_price)
    return nil unless open?
    return nil if margin_used.blank? || margin_used.zero?
    pl = unrealized_pnl(current_price)
    return nil if pl.nil?
    (pl / margin_used * 100).round(2)
  end
end
