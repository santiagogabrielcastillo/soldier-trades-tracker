# frozen_string_literal: true

class PageHeaderComponent < ApplicationComponent
  renders_one :actions

  def initialize(title:, subtitle: nil)
    @title = title
    @subtitle = subtitle
  end

  def wrapper_css
    actions ? "mb-6 flex flex-wrap items-start justify-between gap-3" : "mb-6"
  end
end
