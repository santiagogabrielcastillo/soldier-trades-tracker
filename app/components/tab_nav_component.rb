# frozen_string_literal: true

class TabNavComponent < ApplicationComponent
  Tab = Data.define(:label, :url, :active)

  def initialize(tabs:)
    @tabs = tabs.map { Tab.new(**_1.transform_keys(&:to_sym)) }
  end

  def tab_css(active)
    base = "rounded-lg px-4 py-1.5 text-sm font-medium transition-all duration-150 whitespace-nowrap"
    if active
      "#{base} bg-white text-slate-900 shadow-sm ring-1 ring-slate-200/60"
    else
      "#{base} text-slate-500 hover:text-slate-800 hover:bg-white/60"
    end
  end
end
