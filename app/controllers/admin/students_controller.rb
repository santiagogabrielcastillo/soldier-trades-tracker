# frozen_string_literal: true

class Admin::StudentsController < Admin::BaseController
  before_action :set_student, only: %i[show toggle_active promote]

  def index
    @students   = User.where(role: "user").order(:email).pluck(:id, :email, :active)
    @pl_by_user = Admin::StudentStats.realized_pl_by_user
  end

  def show
    @realized_pl      = Admin::StudentStats.realized_pl_by_user[@student.id].to_f
    @position_counts  = Admin::StudentStats.position_counts_for(@student)
    @recent_positions = Position.for_student(@student)
                                .where(open: false)
                                .order(close_at: :desc)
                                .limit(10)
                                .includes(:exchange_account)
    @stock_portfolios = @student.stock_portfolios.includes(:stock_trades)
    @spot_accounts    = @student.spot_accounts.includes(:spot_transactions)
  end

  def toggle_active
    if @student.update(active: !@student.active)
      redirect_to admin_students_path,
                  notice: t("flash.admin_student_status", email: @student.email, status: @student.active? ? t("admin.shared.active").downcase : t("admin.shared.inactive").downcase)
    else
      redirect_to admin_students_path,
                  alert: @student.errors.full_messages.to_sentence
    end
  end

  def promote
    if @student.update(role: "admin")
      redirect_to admin_students_path, notice: t("flash.admin_student_promoted", email: @student.email)
    else
      redirect_to admin_students_path, alert: @student.errors.full_messages.to_sentence
    end
  end

  private

  def set_student
    @student = User.where(role: "user").find(params[:id])
  end
end
