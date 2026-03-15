# frozen_string_literal: true

class BadgeComponent < ApplicationComponent
  VARIANTS = {
    default: "rounded bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-600",
    success: "rounded bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-700",
    warning: "rounded bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700",
    danger:  "rounded bg-red-100 px-2 py-0.5 text-xs font-medium text-red-700"
  }.freeze

  def initialize(label:, variant: :default)
    @label = label
    @variant_css = VARIANTS.fetch(variant) # raises KeyError for unknown variants
  end
end
