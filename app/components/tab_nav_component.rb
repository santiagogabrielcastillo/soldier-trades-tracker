# frozen_string_literal: true

class TabNavComponent < ApplicationComponent
  Tab = Data.define(:label, :url, :active)

  def initialize(tabs:)
    @tabs = tabs.map { Tab.new(**_1.transform_keys(&:to_sym)) }
  end

  def tab_css(active)
    base = "border-b-2 px-4 py-2 text-sm font-medium"
    if active
      "#{base} border-slate-800 text-slate-900"
    else
      "#{base} border-transparent text-slate-500 hover:border-slate-300 hover:text-slate-700"
    end
  end
end
