module SetsPaperTrailWhodunnit
  extend ActiveSupport::Concern

  included do
    before_action :set_paper_trail_whodunnit
  end

  def set_paper_trail_whodunnit
    return unless current_user
    PaperTrail.request.whodunnit = { id: current_user.id, name: current_user.email, role: current_user.role }.to_json
  end
end
