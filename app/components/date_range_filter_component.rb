# frozen_string_literal: true

class DateRangeFilterComponent < ApplicationComponent
  DATE_FIELD_CLASSES = "rounded-md border border-slate-300 px-3 py-2 text-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500 w-auto min-w-[10rem]".freeze

  def initialize(url:, from:, to:, extra_params: {})
    @url = url
    @from = from
    @to = to
    @extra_params = extra_params
  end
end
