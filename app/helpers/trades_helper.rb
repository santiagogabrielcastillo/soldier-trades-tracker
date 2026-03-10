# frozen_string_literal: true

module TradesHelper
  TRADES_INDEX_PARAMS = %w[view from_date to_date exchange_account_id portfolio_id].freeze

  # Returns a stable key for the current trades index tab for use in preference keys.
  # Used by TradesController (lookup) and UserPreferencesController (save).
  def trades_index_tab_key(view, exchange_account_id = nil, portfolio_id = nil)
    view = view.to_s
    case view
    when "history" then "history"
    when "exchange" then exchange_account_id.present? ? "exchange:#{exchange_account_id}" : "history"
    when "portfolio" then portfolio_id.present? ? "portfolio:#{portfolio_id}" : "portfolio"
    else "history"
    end
  end

  # Resolves visible column IDs for a tab: tab-scoped key → legacy key → default.
  # user: User; tab_key: from trades_index_tab_key.
  # Uses a single query to load both tab-scoped and legacy preference keys.
  def trades_index_visible_column_ids_for(user, tab_key)
    tab_scoped_key = "trades_index_visible_columns:#{tab_key}"
    legacy_key = "trades_index_visible_columns"
    prefs = user.user_preferences.where(key: [ tab_scoped_key, legacy_key ]).index_by(&:key)
    value = prefs[tab_scoped_key]&.value || prefs[legacy_key]&.value
    TradesIndexColumns.visible_columns(value)
  end

  def trades_index_filter_params(overrides = {})
    p = params.permit(TRADES_INDEX_PARAMS).to_h
    p = p.merge(overrides.stringify_keys).delete_if { |_, v| v.blank? }
    p.presence || {}
  end

  def trades_index_cell_content(pos, column_id, roi_val:, pnl_val:, memoized: {})
    open_flag = memoized[:open].nil? ? pos.open? : memoized[:open]
    position_side = memoized[:position_side].nil? ? pos.position_side : memoized[:position_side]
    margin_used = memoized[:margin_used].nil? ? pos.margin_used : memoized[:margin_used]
    total_commission = memoized[:total_commission].nil? ? pos.total_commission : memoized[:total_commission]
    entry_price = memoized[:entry_price].nil? ? pos.entry_price : memoized[:entry_price]
    exit_price = memoized[:exit_price].nil? ? pos.exit_price : memoized[:exit_price]
    open_quantity = memoized[:open_quantity]
    closed_quantity = memoized[:closed_quantity]
    qty_for_display = open_flag ? (open_quantity || pos.open_quantity) : (closed_quantity || pos.closed_quantity)

    case column_id
    when "closed"
      open_flag ? "Open" : pos.close_at&.strftime("%Y-%m-%d")
    when "exchange"
      pos.exchange_account.provider_type&.capitalize
    when "symbol"
      pos.symbol
    when "side"
      position_side&.capitalize || "—"
    when "leverage"
      pos.leverage ? "#{pos.leverage}X" : "—"
    when "margin_used"
      margin_used ? format_money(margin_used) : "—"
    when "roi"
      roi_val.nil? ? "—" : "#{number_with_precision(roi_val, precision: 2)}%"
    when "commission"
      (total_commission || 0).to_d.zero? ? "—" : format_money((total_commission || 0).to_d.abs)
    when "net_pl"
      pnl_val.nil? ? "—" : format_money(pnl_val)
    when "balance"
      format_money(pos.balance)
    when "entry_price"
      entry_price ? format_money(entry_price) : "—"
    when "exit_price"
      exit_price ? format_money(exit_price) : "—"
    when "open_date"
      pos.open_at&.strftime("%Y-%m-%d") || "—"
    when "quantity"
      qty_for_display.present? && !qty_for_display.to_d.zero? ? number_with_precision(qty_for_display.to_d, precision: 8) : "—"
    else
      "—"
    end
  end

  def trades_index_cell_css(pos, column_id, roi_val:, pnl_val:, memoized: {})
    position_side = memoized[:position_side].nil? ? pos.position_side : memoized[:position_side]
    base = "whitespace-nowrap px-6 py-4 text-sm "
    case column_id
    when "side"
      base + (position_side == "long" ? "text-emerald-600" : position_side == "short" ? "text-red-600" : "text-slate-500")
    when "roi"
      base + (roi_val && roi_val >= 0 ? "text-emerald-600 text-right" : roi_val ? "text-red-600 text-right" : "text-slate-500 text-right")
    when "net_pl"
      base + (pnl_val.nil? ? "text-slate-500 text-right" : pnl_val >= 0 ? "text-emerald-600 text-right" : "text-red-600 text-right")
    when "margin_used", "commission", "balance", "entry_price", "exit_price"
      base + "text-right text-slate-900"
    when "exchange", "leverage", "quantity", "open_date"
      base + "text-slate-600"
    when "symbol"
      base + "font-medium text-slate-900"
    else
      base + "text-slate-900"
    end
  end
end
