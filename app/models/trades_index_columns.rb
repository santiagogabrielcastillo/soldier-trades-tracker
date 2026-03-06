# frozen_string_literal: true

# Registry of column IDs and labels for the trades index table. Used by the view and column-visibility modal.
# Preference key: UserPreference key "trades_index_visible_columns"; value = JSON array of column IDs.
module TradesIndexColumns
  ALL_IDS = %w[
    closed
    exchange
    symbol
    side
    leverage
    margin_used
    roi
    commission
    net_pl
    balance
    entry_price
    exit_price
    open_date
    quantity
  ].freeze

  # Default visible set: original 10 columns + entry_price.
  DEFAULT_VISIBLE = %w[
    closed
    exchange
    symbol
    side
    leverage
    margin_used
    roi
    commission
    net_pl
    balance
    entry_price
  ].freeze

  LABELS = {
    "closed" => "Closed",
    "exchange" => "Exchange",
    "symbol" => "Symbol",
    "side" => "Side",
    "leverage" => "Leverage",
    "margin_used" => "Margin used",
    "roi" => "ROI",
    "commission" => "Commission",
    "net_pl" => "Net P&L",
    "balance" => "Balance",
    "entry_price" => "Entry price",
    "exit_price" => "Exit price",
    "open_date" => "Open date",
    "quantity" => "Quantity"
  }.freeze

  def self.visible_columns(ids)
    return DEFAULT_VISIBLE.dup if ids.blank?
    ids = Array(ids).map(&:to_s)
    # Only allow IDs that exist in ALL_IDS; preserve order of ALL_IDS for display
    ALL_IDS.select { |id| ids.include?(id) }
  end
end
