# frozen_string_literal: true

class UserPreference < ApplicationRecord
  belongs_to :user

  validates :key, presence: true, uniqueness: { scope: :user_id }
  validate :value_must_be_present

  private

  def value_must_be_present
    errors.add(:value, "can't be blank") if value.blank?
  end
end
