# frozen_string_literal: true

class StatCardComponent < ApplicationComponent
  def initialize(label:, value:, signed: false, color_value: nil, value_html: {})
    @label = label
    @value = value
    @signed = signed
    # color_value: raw numeric used for sign detection when signed: true.
    # Falls back to @value if not provided (for cases where value is already numeric).
    @color_value = color_value.nil? ? value : color_value
    @value_html = value_html
  end

  def value_css
    return "text-2xl font-semibold text-slate-800" unless @signed

    "text-2xl font-semibold #{pl_color_class(@color_value)}"
  end

  def display_value
    @value.nil? ? "—" : @value
  end
end
