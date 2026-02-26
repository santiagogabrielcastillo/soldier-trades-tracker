class Trade < ApplicationRecord
  belongs_to :exchange_account

  validates :exchange_reference_id, uniqueness: { scope: :exchange_account_id }

  # Parses raw_payload["leverage"] (e.g. "10X") to a number. Returns nil if missing or unparseable.
  def leverage_from_raw
    raw = raw_payload || {}
    str = raw["leverage"].to_s.strip
    return nil if str.blank?
    str.sub(/\A(\d+).*\z/, "\\1").to_i.then { |n| n.positive? ? n : nil }
  end

  # Notional (position size) from raw: avgPrice * executedQty. Used for margin = notional / leverage.
  def notional_from_raw
    raw = raw_payload || {}
    avg = (raw["avgPrice"] || raw["price"] || 0).to_d
    qty = (raw["executedQty"] || raw["executed_qty"] || raw["origQty"] || 0).to_d
    (avg * qty).to_d
  end
end
