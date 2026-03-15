# frozen_string_literal: true

class StatCardComponent < ApplicationComponent
  def initialize(label:, value:, signed: false, color_value: nil)
    @label = label
    @value = value
    @signed = signed
    # color_value: raw numeric used for sign detection when signed: true.
    # Falls back to @value if not provided (for cases where value is already numeric).
    @color_value = color_value.nil? ? value : color_value
  end

  def value_css
    return "text-xl font-semibold text-slate-900" unless @signed

    "text-xl font-semibold #{pl_color_class(@color_value)}"
  end

  def display_value
    @value.nil? ? "—" : @value
  end
end
