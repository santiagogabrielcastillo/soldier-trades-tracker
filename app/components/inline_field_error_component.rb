# frozen_string_literal: true

class InlineFieldErrorComponent < ApplicationComponent
  def initialize(errors:, attribute:)
    @errors = errors
    @attribute = attribute
  end

  def render?
    @errors[@attribute].any?
  end
end
