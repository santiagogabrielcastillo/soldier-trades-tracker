# frozen_string_literal: true

class Admin::AdminsController < Admin::BaseController
  before_action :set_admin, only: %i[show toggle_active demote]
  before_action :require_super_admin, only: %i[toggle_active demote]

  def index
    @admins     = User.where(role: "admin").order(:email).pluck(:id, :email, :active)
    @pl_by_user = Admin::StudentStats.realized_pl_by_user
  end

  def show
    @realized_pl      = Admin::StudentStats.realized_pl_by_user[@admin.id].to_f
    @position_counts  = Admin::StudentStats.position_counts_for(@admin)
    @recent_positions = Position.for_student(@admin)
                                .where(open: false)
                                .order(close_at: :desc)
                                .limit(10)
                                .includes(:exchange_account)
    @stock_portfolios = @admin.stock_portfolios.includes(:stock_trades)
    @spot_accounts    = @admin.spot_accounts.includes(:spot_transactions)
  end

  def toggle_active
    if @admin.update(active: !@admin.active)
      redirect_to admin_admins_path,
                  notice: t("flash.admin_student_status", email: @admin.email, status: @admin.active? ? t("admin.shared.active").downcase : t("admin.shared.inactive").downcase)
    else
      redirect_to admin_admins_path,
                  alert: @admin.errors.full_messages.to_sentence
    end
  end

  def demote
    if @admin.update(role: "user")
      redirect_to admin_admins_path, notice: t("flash.admin_admin_demoted", email: @admin.email)
    else
      redirect_to admin_admins_path, alert: @admin.errors.full_messages.to_sentence
    end
  end

  private

  def set_admin
    @admin = User.where(role: "admin").find(params[:id])
  end
end
