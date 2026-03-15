# frozen_string_literal: true

class EmptyStateComponent < ApplicationComponent
  def initialize(message:, padding: "p-12")
    @message = message
    @padding = padding
  end
end
