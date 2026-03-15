# frozen_string_literal: true

class ErrorSummaryComponent < ApplicationComponent
  def initialize(model:)
    @model = model
  end

  def render?
    @model.errors.any?
  end
end
