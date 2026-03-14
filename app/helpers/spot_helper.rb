# frozen_string_literal: true

module SpotHelper
  SPOT_INDEX_PARAMS = %w[view from_date to_date token side].freeze

  def spot_index_filter_params(overrides = {})
    p = params.permit(SPOT_INDEX_PARAMS).to_h
    p = p.merge(overrides.stringify_keys).delete_if { |_, v| v.blank? }
    p.presence || {}
  end
end
