# frozen_string_literal: true

class DataTableComponent < ApplicationComponent
  renders_many :rows, "DataTableComponent::RowComponent"

  def initialize(columns:)
    @columns = columns # Array of { label: String, classes: String (optional) }
  end

  class RowComponent < ViewComponent::Base
    def initialize(classes: "")
      @classes = classes
    end
  end
end
