# frozen_string_literal: true

class ApplicationComponent < ViewComponent::Base
  include ApplicationHelper

  private

  # Delegates to ApplicationHelper#pl_color_class — single source of truth.
  def pl_color_class(value)
    helpers.pl_color_class(value)
  end
end
