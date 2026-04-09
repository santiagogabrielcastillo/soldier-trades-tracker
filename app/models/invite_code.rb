# frozen_string_literal: true

class InviteCode < ApplicationRecord
  validates :code, presence: true, uniqueness: true
  validates :expires_at, presence: true,
                         comparison: { greater_than: -> { Time.current }, on: :create }

  # Returns the single current (non-expired) invite code, or nil if none exists.
  def self.current
    where("expires_at > ?", Time.current).order(created_at: :desc).first
  end

  # Atomically rotates the invite code by updating the existing row (or creating
  # one if none exists). Updating rather than delete+create means there is never
  # a window where no code exists — the row is always present, only its values change.
  def self.rotate!(expires_at:)
    transaction do
      record = first || new
      record.assign_attributes(code: SecureRandom.hex(16), expires_at: expires_at)
      record.save!
      record
    end
  end

  def valid_for_registration?
    expires_at.present? && expires_at > Time.current
  end
end
