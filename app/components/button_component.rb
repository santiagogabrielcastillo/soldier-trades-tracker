# frozen_string_literal: true

class ButtonComponent < ApplicationComponent
  VARIANTS = {
    primary: "rounded-md bg-slate-800 px-4 py-2 text-sm font-medium text-white hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-slate-500",
    secondary: "rounded-md border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
  }.freeze

  def initialize(label:, variant: :primary, href: nil, **html_options)
    @label = label
    @href = href
    base_class = VARIANTS.fetch(variant)
    merged_class = [ base_class, html_options[:class] ].compact.join(" ")
    @html_options = html_options.except(:class).merge(class: merged_class).symbolize_keys
  end
end
