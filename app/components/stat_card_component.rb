# frozen_string_literal: true

class StatCardComponent < ApplicationComponent
  def initialize(label:, value:, signed: false)
    @label = label
    @value = value
    @signed = signed
  end

  def value_css
    return "text-xl font-semibold text-slate-900" unless @signed

    "text-xl font-semibold #{pl_color_class(@value)}"
  end

  def display_value
    @value.nil? ? "—" : @value
  end
end
