class AuditBadgeComponent < ApplicationComponent
  def initialize(record:, owner:)
    @record = record
    @owner  = owner
  end

  def render?
    last_version_by_admin?
  end

  def actor_name
    @actor_name ||= actor_data["name"] || "Admin"
  end

  def actor_at
    @record.versions.last&.created_at
  end

  private

  def last_version_by_admin?
    data = actor_data
    data.present? && data["id"] != @owner.id && %w[admin super_admin].include?(data["role"])
  end

  def actor_data
    @actor_data ||= begin
      whodunnit = @record.versions.last&.whodunnit
      whodunnit ? JSON.parse(whodunnit) : {}
    rescue JSON::ParserError
      {}
    end
  end
end
