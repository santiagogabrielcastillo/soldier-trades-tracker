# frozen_string_literal: true

class CardComponent < ApplicationComponent
  def initialize(heading: nil, margin: nil, **html_options)
    @heading = heading
    @margin = margin
    base_class = "rounded-lg border border-slate-200 bg-white p-6 shadow-sm"
    merged_class = [ base_class, margin, html_options[:class] ].compact.join(" ")
    @html_options = html_options.except(:class).merge(class: merged_class).symbolize_keys
  end
end
