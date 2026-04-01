# frozen_string_literal: true

module HasSingleDefault
  extend ActiveSupport::Concern

  included do
    before_save :clear_other_defaults, if: :default?
  end

  private

  def clear_other_defaults
    self.class.where(user_id: user_id).where.not(id: id).update_all(default: false)
  end
end
