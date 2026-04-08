# frozen_string_literal: true

class DateRangeFilterComponent < ApplicationComponent
  DATE_FIELD_CLASSES = "rounded-md border border-slate-300 px-3 py-2 text-sm focus:border-slate-500 focus:outline-none focus:ring-1 focus:ring-slate-500 w-auto min-w-[10rem]".freeze
  CLEAR_LINK_CLASSES = "rounded-md border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-slate-500".freeze

  # extra_params: hash of hidden field name => value pairs (e.g. view, exchange_account_id)
  # clear_url:    URL for the "Clear filters" link (omitted if nil)
  # extra_fields slot: visible filter fields (selects, text inputs) rendered after the To date
  renders_one :extra_fields

  def initialize(url:, from:, to:, extra_params: {}, clear_url: nil)
    @url = url
    @from = from
    @to = to
    @extra_params = extra_params
    @clear_url = clear_url
  end
end
