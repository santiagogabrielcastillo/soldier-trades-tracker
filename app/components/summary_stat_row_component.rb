# frozen_string_literal: true

class SummaryStatRowComponent < ApplicationComponent
  def initialize(mb: 6)
    @mb = mb
  end

  def row_css
    "flex flex-wrap items-baseline gap-6 mb-#{@mb}"
  end
end
