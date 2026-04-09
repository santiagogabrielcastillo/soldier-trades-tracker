# frozen_string_literal: true

module Admin
  module StudentStats
    # Returns { user_id (int) => realized_pl (float) } for all non-admin students.
    # Students with no closed positions are absent from the hash (treat as 0.0 at call site).
    def self.realized_pl_by_user
      Position
        .joins(exchange_account: :user)
        .where(open: false)
        .where(users: { admin: false })
        .group("users.id")
        .sum(:net_pl)
        .transform_values(&:to_f)
    end

    # Returns array of { user_id:, email:, realized_pl:, active: } sorted by descending P&L.
    # Uses pluck to avoid loading full User objects into memory.
    def self.leaderboard(pl_by_user)
      User.where(admin: false)
          .pluck(:id, :email, :active)
          .map { |id, email, active| { user_id: id, email: email, realized_pl: pl_by_user.fetch(id, 0.0), active: active } }
          .sort_by { |r| -r[:realized_pl] }
    end

    # Returns { true => open_count, false => closed_count } for a given student.
    # One query via GROUP BY open instead of two separate count queries.
    def self.position_counts_for(user)
      Position.for_student(user)
              .group(:open)
              .count
    end
  end
end
