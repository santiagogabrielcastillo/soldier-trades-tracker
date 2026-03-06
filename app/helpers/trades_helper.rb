# frozen_string_literal: true

module TradesHelper
  TRADES_INDEX_PARAMS = %w[view from_date to_date exchange_account_id portfolio_id].freeze

  def trades_index_filter_params(overrides = {})
    p = params.permit(TRADES_INDEX_PARAMS).to_h
    p = p.merge(overrides.stringify_keys).delete_if { |_, v| v.blank? }
    p.presence || {}
  end

  def trades_index_cell_content(pos, column_id, roi_val:, pnl_val:)
    case column_id
    when "closed"
      pos.open? ? "Open" : pos.close_at&.strftime("%Y-%m-%d")
    when "exchange"
      pos.exchange_account.provider_type&.capitalize
    when "symbol"
      pos.symbol
    when "side"
      pos.position_side&.capitalize || "—"
    when "leverage"
      pos.leverage ? "#{pos.leverage}X" : "—"
    when "margin_used"
      pos.margin_used ? format_money(pos.margin_used) : "—"
    when "roi"
      roi_val.nil? ? "—" : "#{number_with_precision(roi_val, precision: 2)}%"
    when "commission"
      pos.total_commission.zero? ? "—" : format_money(pos.total_commission.abs)
    when "net_pl"
      pnl_val.nil? ? "—" : format_money(pnl_val)
    when "balance"
      format_money(pos.balance)
    when "entry_price"
      pos.entry_price ? format_money(pos.entry_price) : "—"
    when "exit_price"
      pos.exit_price ? format_money(pos.exit_price) : "—"
    when "open_date"
      pos.open_at&.strftime("%Y-%m-%d") || "—"
    when "quantity"
      qty = pos.open? ? pos.open_quantity : pos.closed_quantity
      qty.present? && !qty.zero? ? number_with_precision(qty, precision: 8) : "—"
    else
      "—"
    end
  end

  def trades_index_cell_css(pos, column_id, roi_val:, pnl_val:)
    base = "whitespace-nowrap px-6 py-4 text-sm "
    case column_id
    when "side"
      base + (pos.position_side == "long" ? "text-emerald-600" : pos.position_side == "short" ? "text-red-600" : "text-slate-500")
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
