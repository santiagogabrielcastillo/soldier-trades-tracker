# frozen_string_literal: true

class BreadcrumbComponent < ApplicationComponent
  Crumb = Data.define(:label, :url)

  # Pass items as an array of hashes: [{ label: "Trades", url: trades_path }, { label: "Portfolios" }]
  # The last item is the current page (no url needed).
  def initialize(items:)
    @crumbs = items.map { Crumb.new(label: _1[:label], url: _1[:url]) }
  end
end
