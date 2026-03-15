# frozen_string_literal: true

module StocksHelper
  STOCKS_INDEX_PARAMS = %w[view from_date to_date ticker side].freeze

  def stocks_index_filter_params(overrides = {})
    p = params.permit(STOCKS_INDEX_PARAMS).to_h
    p = p.merge(overrides.stringify_keys).delete_if { |_, v| v.blank? }
    p.presence || {}
  end
end
