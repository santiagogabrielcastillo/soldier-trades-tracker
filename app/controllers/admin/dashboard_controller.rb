# frozen_string_literal: true

class Admin::DashboardController < Admin::BaseController
  def show
    students          = User.where(admin: false)
    @total_students   = students.count
    @active_students  = students.where(active: true).count
    @pl_by_user       = Admin::StudentStats.realized_pl_by_user
    @profitable_count = @pl_by_user.count { |_, pl| pl > 0 }
    @profitable_pct   = @total_students > 0 ? (@profitable_count.to_f / @total_students * 100).round(1) : 0
    @total_realized   = @pl_by_user.values.sum
    @avg_realized     = @total_students > 0 ? @total_realized / @total_students : 0
    @leaderboard      = Admin::StudentStats.leaderboard(@pl_by_user)
  end
end
